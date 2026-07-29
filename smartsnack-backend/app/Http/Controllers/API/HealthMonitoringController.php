<?php

namespace App\Http\Controllers\API;

use App\Http\Controllers\Controller;
use App\Models\BodyMetric;
use App\Models\BodyTemperature;
use App\Models\HealthCheck;
use App\Models\HealthResult;
use App\Models\HeartRate;
use App\Services\HealthMonitoringService;
use Carbon\Carbon;
use Carbon\CarbonInterface;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Throwable;

// Controller ini menangani seluruh alur monitoring kesehatan anak:
// 1. Cek detak jantung (MAX30102)
// 2. Cek suhu tubuh (MLX90614)
// 3. Cek berat badan (LoadCell + HX711)
// 4. Cek tinggi badan (HC-SR04 ultrasonik)
// 5. Proses hasil: evaluasi status kesehatan (normal/perlu_perhatian) tanpa ML
// 6. Setelah berhasil, buka servo box otomatis via MQTT
class HealthMonitoringController extends Controller
{
    public function __construct(private readonly HealthMonitoringService $service)
    {
    }

    private function getOrCreateCheck(Request $request): HealthCheck
    {
        $checkId = $request->input('check_id');
        if ($checkId !== null && is_numeric($checkId)) {
            $check = HealthCheck::query()
                ->where('id', (int) $checkId)
                ->where('user_id', $request->user()->id)
                ->first();
            if ($check !== null) {
                return $check;
            }
        }

        return HealthCheck::create([
            'user_id'    => $request->user()->id,
            'created_at' => now(),
        ]);
    }

    // Alur: app trigger cek detak jantung → backend command device via MQTT → simpan hasil → kirim ke app.
    public function checkHeartRate(Request $request): JsonResponse
    {
        @set_time_limit(0);
        try {
            $check = $this->getOrCreateCheck($request);

            $sensor = $this->service->fetchHeartRate(
                checkId: $check->id,
                userId: (int) $request->user()->id
            );
            HeartRate::query()->updateOrCreate(
                ['check_id' => $check->id],
                ['heart_rate' => (int) round((float) $sensor['value'])]
            );

            return successResponse([
                'check_id'   => $check->id,
                'heart_rate' => (float) $sensor['value'],
                'source'     => (string) $sensor['source'],
                'transport'  => (string) ($sensor['transport'] ?? 'mqtt'),
                'device_id'  => (string) ($sensor['device_id'] ?? ''),
                'checked_at' => $this->toIso8601($check->created_at),
            ], 'Data detak jantung berhasil diambil.');
        } catch (Throwable $e) {
            return errorResponse($e->getMessage(), null, 422);
        }
    }

    // Alur: app trigger cek suhu tubuh → backend command device via MQTT → simpan suhu → kirim hasil.
    public function checkBodyTemperature(Request $request): JsonResponse
    {
        @set_time_limit(0);
        try {
            $check = $this->getOrCreateCheck($request);

            $sensor = $this->service->fetchBodyTemperature(
                checkId: $check->id,
                userId: (int) $request->user()->id
            );

            BodyTemperature::query()->updateOrCreate(
                ['check_id' => $check->id],
                ['temperature' => round((float) $sensor['value'], 2)]
            );

            return successResponse([
                'check_id'   => $check->id,
                'body_temp'  => (float) $sensor['value'],
                'source'     => (string) $sensor['source'],
                'transport'  => (string) ($sensor['transport'] ?? 'mqtt'),
                'device_id'  => (string) ($sensor['device_id'] ?? ''),
                'checked_at' => $this->toIso8601($check->created_at),
            ], 'Data suhu tubuh berhasil diambil.');
        } catch (Throwable $e) {
            return errorResponse($e->getMessage(), null, 422);
        }
    }

    // Alur: app trigger cek berat badan → backend command LoadCell via MQTT → simpan → kirim hasil.
    public function checkWeight(Request $request): JsonResponse
    {
        @set_time_limit(0);
        try {
            $check = $this->getOrCreateCheck($request);

            $sensor = $this->service->fetchWeight(
                checkId: $check->id,
                userId: (int) $request->user()->id
            );

            BodyMetric::query()->updateOrCreate(
                ['check_id' => $check->id],
                ['weight' => round((float) $sensor['value'], 2)]
            );

            return successResponse([
                'check_id'   => $check->id,
                'weight_kg'  => (float) $sensor['value'],
                'source'     => (string) $sensor['source'],
                'transport'  => (string) ($sensor['transport'] ?? 'mqtt'),
                'device_id'  => (string) ($sensor['device_id'] ?? ''),
                'checked_at' => $this->toIso8601($check->created_at),
            ], 'Data berat badan berhasil diambil.');
        } catch (Throwable $e) {
            return errorResponse($e->getMessage(), null, 422);
        }
    }

    // Alur: app trigger cek tinggi badan → backend command HC-SR04 via MQTT → simpan → kirim hasil.
    public function checkHeight(Request $request): JsonResponse
    {
        @set_time_limit(0);
        try {
            $check = $this->getOrCreateCheck($request);

            $sensor = $this->service->fetchHeight(
                checkId: $check->id,
                userId: (int) $request->user()->id
            );

            BodyMetric::query()->updateOrCreate(
                ['check_id' => $check->id],
                ['height' => round((float) $sensor['value'], 2)]
            );

            return successResponse([
                'check_id'   => $check->id,
                'height_cm'  => (float) $sensor['value'],
                'source'     => (string) $sensor['source'],
                'transport'  => (string) ($sensor['transport'] ?? 'mqtt'),
                'device_id'  => (string) ($sensor['device_id'] ?? ''),
                'checked_at' => $this->toIso8601($check->created_at),
            ], 'Data tinggi badan berhasil diambil.');
        } catch (Throwable $e) {
            return errorResponse($e->getMessage(), null, 422);
        }
    }

    // Alur: app kirim check_id → backend ambil semua data sensor, hitung BMI,
    // evaluasi status (normal/perlu_perhatian) tanpa ML, simpan hasil,
    // lalu publish MQTT untuk buka servo box selama 10 detik.
    public function analyze(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'check_id' => 'required|integer|exists:health_checks,id',
            'age' => 'nullable|integer|min:1',
            'gender' => 'nullable|in:Male,Female',
        ]);

        $check = HealthCheck::query()
            ->where('id', $validated['check_id'])
            ->where('user_id', $request->user()->id)
            ->firstOrFail();

        $user   = $request->user();
        $heart  = HeartRate::query()->where('check_id', $check->id)->latest('id')->first();
        $temp   = BodyTemperature::query()->where('check_id', $check->id)->latest('id')->first();
        $metric = BodyMetric::query()->where('check_id', $check->id)->first();

        if ($heart === null || $temp === null) {
            return errorResponse('Data sensor belum lengkap. Cek detak jantung dan suhu tubuh terlebih dahulu.', null, 422);
        }

        $weightKg = $metric ? (float) $metric->weight : null;
        $heightCm = $metric ? (float) $metric->height : null;

        if ($weightKg === null || $weightKg <= 0) {
            return errorResponse('Data berat badan belum tersedia. Lakukan cek berat badan terlebih dahulu.', null, 422);
        }
        if ($heightCm === null || $heightCm <= 0) {
            return errorResponse('Data tinggi badan belum tersedia. Lakukan cek tinggi badan terlebih dahulu.', null, 422);
        }

        // Hitung BMI
        $heightM = $heightCm / 100;
        $bmi     = round($weightKg / ($heightM * $heightM), 2);

        // Ambil age dari input, fallback ke profil user
        $age    = (int) ($request->input('age') ?? $user->age ?? 10);
        $gender = (string) ($request->input('gender') ?? $user->gender ?? 'Male');

        // Evaluasi status kesehatan (rule-based, tanpa ML)
        $evaluation = $this->service->evaluateHealthStatus([
            'heart_rate' => (float) $heart->heart_rate,
            'body_temp'  => (float) $temp->temperature,
            'bmi'        => $bmi,
            'age'        => $age,
        ]);

        DB::transaction(function () use ($check, $user, $weightKg, $heightCm, $bmi, $age, $gender, $evaluation): void {
            BodyMetric::query()->updateOrCreate(
                ['check_id' => $check->id],
                [
                    'age'    => $age,
                    'gender' => $gender,
                    'height' => round($heightCm, 2),
                    'weight' => round($weightKg, 2),
                    'bmi'    => $bmi,
                ]
            );

            HealthResult::query()->updateOrCreate(
                ['check_id' => $check->id],
                [
                    'heart_status'   => $evaluation['heart_status'],
                    'temp_status'    => $evaluation['temp_status'],
                    'bmi_status'     => $evaluation['bmi_status'],
                    'overall_status' => $evaluation['overall_status'],
                ]
            );
        });

        // Buka servo box setelah cek kesehatan berhasil (tidak bergantung hasilnya)
        try {
            $this->service->publishOpenBox();
        } catch (\Throwable) {
            // Tidak gagalkan response jika MQTT buka box gagal
        }

        return successResponse([
            'check_id'       => $check->id,
            'heart_rate'     => (float) $heart->heart_rate,
            'body_temp'      => (float) $temp->temperature,
            'weight_kg'      => round($weightKg, 2),
            'height_cm'      => round($heightCm, 2),
            'bmi'            => $bmi,
            'age'            => $age,
            'gender'         => $gender,
            'heart_status'   => $evaluation['heart_status'],
            'temp_status'    => $evaluation['temp_status'],
            'bmi_status'     => $evaluation['bmi_status'],
            'overall_status' => $evaluation['overall_status'],
            'checked_at'     => $this->toIso8601($check->created_at),
        ], 'Monitoring kesehatan berhasil diproses.');
    }

    // Ambil riwayat monitoring kesehatan user dari database.
    public function history(Request $request): JsonResponse
    {
        $rows = HealthCheck::query()
            ->where('health_checks.user_id', $request->user()->id)
            ->leftJoin('heart_rates',       'heart_rates.check_id',       '=', 'health_checks.id')
            ->leftJoin('body_temperatures', 'body_temperatures.check_id', '=', 'health_checks.id')
            ->leftJoin('body_metrics',      'body_metrics.check_id',      '=', 'health_checks.id')
            ->leftJoin('health_results',    'health_results.check_id',    '=', 'health_checks.id')
            ->whereNotNull('body_metrics.id')
            ->whereNotNull('health_results.id')
            ->orderByDesc('health_checks.created_at')
            ->get([
                'health_checks.id as check_id',
                'health_checks.created_at',
                'heart_rates.heart_rate',
                'body_temperatures.temperature',
                'body_metrics.age',
                'body_metrics.gender',
                'body_metrics.height',
                'body_metrics.weight',
                'body_metrics.bmi',
                'health_results.heart_status',
                'health_results.temp_status',
                'health_results.bmi_status',
                'health_results.overall_status',
            ])
            ->map(function ($row) {
                return [
                    'check_id'       => (int) $row->check_id,
                    'heart_rate'     => (float) ($row->heart_rate ?? 0),
                    'body_temp'      => (float) ($row->temperature ?? 0),
                    'age'            => (int) ($row->age ?? 0),
                    'gender'         => (string) ($row->gender ?? 'Male'),
                    'height_cm'      => (float) ($row->height ?? 0),
                    'weight_kg'      => (float) ($row->weight ?? 0),
                    'bmi'            => (float) ($row->bmi ?? 0),
                    'heart_status'   => (string) ($row->heart_status   ?? 'normal'),
                    'temp_status'    => (string) ($row->temp_status    ?? 'normal'),
                    'bmi_status'     => (string) ($row->bmi_status     ?? 'normal'),
                    'overall_status' => (string) ($row->overall_status ?? 'normal'),
                    'checked_at'     => $this->toIso8601($row->created_at),
                ];
            })
            ->values();

        return successResponse($rows, 'Riwayat monitoring kesehatan berhasil diambil.');
    }

    private function toIso8601(mixed $value): ?string
    {
        if ($value === null || $value === '') {
            return null;
        }

        if ($value instanceof CarbonInterface) {
            return $value->toIso8601String();
        }

        try {
            return Carbon::parse((string) $value)->toIso8601String();
        } catch (Throwable) {
            return (string) $value;
        }
    }
}
