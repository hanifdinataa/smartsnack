<?php

namespace App\Http\Controllers\API;

use App\Http\Controllers\Controller;
use App\Models\BodyMetric;
use App\Models\BodyTemperature;
use App\Models\DiabetesPrediction;
use App\Models\HealthCheck;
use App\Models\HeartRate;
use App\Services\HealthMonitoringService;
use Carbon\Carbon;
use Carbon\CarbonInterface;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Throwable;

class HealthMonitoringController extends Controller
{
    public function __construct(private readonly HealthMonitoringService $service)
    {
    }


    // Alur fungsi ini: app trigger cek detak jantung, backend command device via MQTT, simpan hasil sensor, lalu kirim ke app.
    public function checkHeartRate(Request $request): JsonResponse
    {
        @set_time_limit(0);
        try {
            $check = HealthCheck::create([
                'user_id' => $request->user()->id,
                'created_at' => now(),
            ]);

            $sensor = $this->service->fetchHeartRate(
                checkId: $check->id,
                userId: (int) $request->user()->id
            );
            HeartRate::create([
                'check_id' => $check->id,
                'heart_rate' => (int) round((float) $sensor['value']),
            ]);

            return successResponse([
                'check_id' => $check->id,
                'heart_rate' => (float) $sensor['value'],
                'source' => (string) $sensor['source'],
                'transport' => (string) ($sensor['transport'] ?? 'mqtt'),
                'device_id' => (string) ($sensor['device_id'] ?? ''),
                'checked_at' => $this->toIso8601($check->created_at),
            ], 'Data detak jantung berhasil diambil.');
        } catch (Throwable $e) {
            return errorResponse($e->getMessage(), null, 422);
        }
    }



    // Alur fungsi ini: app trigger cek suhu, backend command device via MQTT, simpan suhu ke database, lalu kirim hasil.
    public function checkBodyTemperature(Request $request): JsonResponse
    {
        @set_time_limit(0);
        $validated = $request->validate([
            'check_id' => 'required|integer|exists:health_checks,id',
        ]);

        $check = HealthCheck::query()
            ->where('id', $validated['check_id'])
            ->where('user_id', $request->user()->id)
            ->firstOrFail();

        try {
            $sensor = $this->service->fetchBodyTemperature(
                checkId: $check->id,
                userId: (int) $request->user()->id
            );

            BodyTemperature::query()->updateOrCreate(
                ['check_id' => $check->id],
                ['temperature' => round((float) $sensor['value'], 2)]
            );

            return successResponse([
                'check_id' => $check->id,
                'body_temp' => (float) $sensor['value'],
                'source' => (string) $sensor['source'],
                'transport' => (string) ($sensor['transport'] ?? 'mqtt'),
                'device_id' => (string) ($sensor['device_id'] ?? ''),
                'checked_at' => $this->toIso8601($check->created_at),
            ], 'Data suhu tubuh berhasil diambil.');
        } catch (Throwable $e) {
            return errorResponse($e->getMessage(), null, 422);
        }
    }






    // Alur fungsi ini: app kirim data biometrik+check_id, backend gabung data sensor lalu panggil model XGBoost, simpan hasil risiko.
    public function analyze(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'check_id' => 'required|integer|exists:health_checks,id',
            'age' => 'required|integer|min:1|max:120',
            'gender' => 'required|in:Male,Female',
            'height_cm' => 'required|numeric|min:50|max:260',
            'weight_kg' => 'required|numeric|min:10|max:350',
            'bmi' => 'required|numeric|min:5|max:80',
        ]);

        $check = HealthCheck::query()
            ->where('id', $validated['check_id'])
            ->where('user_id', $request->user()->id)
            ->firstOrFail();

        $heart = HeartRate::query()->where('check_id', $check->id)->latest('id')->first();
        $temp = BodyTemperature::query()->where('check_id', $check->id)->latest('id')->first();

        if ($heart === null || $temp === null) {
            return errorResponse('Data sensor belum lengkap. Cek detak jantung dan suhu tubuh terlebih dahulu.', null, 422);
        }

        $payload = [
            'heart_rate' => (float) $heart->heart_rate,
            'body_temp' => (float) $temp->temperature,
            'age' => (int) $validated['age'],
            'gender' => (string) $validated['gender'],
            'height_cm' => (float) $validated['height_cm'],
            'weight_kg' => (float) $validated['weight_kg'],
            'bmi' => (float) $validated['bmi'],
        ];

        $risk = $this->service->analyzeRisk($payload);

        DB::transaction(function () use ($check, $validated, $risk): void {
            BodyMetric::query()->updateOrCreate(
                ['check_id' => $check->id],
                [
                    'age' => (int) $validated['age'],
                    'gender' => (string) $validated['gender'],
                    'height' => round((float) $validated['height_cm'], 2),
                    'weight' => round((float) $validated['weight_kg'], 2),
                    'bmi' => round((float) $validated['bmi'], 2),
                ]
            );

            DiabetesPrediction::query()->updateOrCreate(
                ['check_id' => $check->id],
                ['result' => (string) $risk['risk']]
            );
        });

        return successResponse([
            'check_id' => $check->id,
            'heart_rate' => (float) $heart->heart_rate,
            'body_temp' => (float) $temp->temperature,
            'age' => (int) $validated['age'],
            'gender' => (string) $validated['gender'],
            'height_cm' => (float) $validated['height_cm'],
            'weight_kg' => (float) $validated['weight_kg'],
            'bmi' => (float) $validated['bmi'],
            'risk_diabetes' => (string) $risk['risk'],
            'algorithm' => (string) $risk['algorithm'],
            'risk_percent' => isset($risk['risk_percent']) ? (float) $risk['risk_percent'] : null,
            'checked_at' => $this->toIso8601($check->created_at),
        ], 'Analisis dini risiko diabetes berhasil diproses.');
    }






    // Alur fungsi ini: request dari app diproses di controller (validasi + service/model/database), lalu response dikirim balik ke aplikasi.
    public function history(Request $request): JsonResponse
    {
        $rows = HealthCheck::query()
            ->where('health_checks.user_id', $request->user()->id)
            ->leftJoin('heart_rates', 'heart_rates.check_id', '=', 'health_checks.id')
            ->leftJoin('body_temperatures', 'body_temperatures.check_id', '=', 'health_checks.id')
            ->leftJoin('body_metrics', 'body_metrics.check_id', '=', 'health_checks.id')
            ->leftJoin('diabetes_predictions', 'diabetes_predictions.check_id', '=', 'health_checks.id')
            ->whereNotNull('body_metrics.id')
            ->whereNotNull('diabetes_predictions.id')
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
                'diabetes_predictions.result',
            ])
            ->map(function ($row) {
                return [
                    'check_id' => (int) $row->check_id,
                    'heart_rate' => (float) ($row->heart_rate ?? 0),
                    'body_temp' => (float) ($row->temperature ?? 0),
                    'age' => (int) ($row->age ?? 0),
                    'gender' => (string) ($row->gender ?? 'Male'),
                    'height_cm' => (float) ($row->height ?? 0),
                    'weight_kg' => (float) ($row->weight ?? 0),
                    'bmi' => (float) ($row->bmi ?? 0),
                    'risk_diabetes' => strtoupper((string) ($row->result ?? 'TIDAK')),
                    'algorithm' => 'xgboost_service',
                    'checked_at' => $this->toIso8601($row->created_at),
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


