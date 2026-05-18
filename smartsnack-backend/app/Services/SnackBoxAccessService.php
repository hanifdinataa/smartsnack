<?php

namespace App\Services;

use App\Models\DiabetesPrediction;
use App\Models\SnackBoxDevice;
use Illuminate\Support\Facades\DB;
use RuntimeException;

class SnackBoxAccessService
{
    public function defaultDeviceId(): string
    {
        return trim((string) config('services.snack_box.device_id', config('services.mqtt.device_id', 'esp32_health_01')));
    }

    public function servoOpenDurationMs(): int
    {
        return max(500, (int) config('services.snack_box.servo_open_duration_ms', 3000));
    }

    public function minRemainingToOpen(string $risk): float
    {
        if ($risk === 'YES') {
            return max(0.0, (float) config('services.snack_box.min_remaining_to_open_yes', 3));
        }

        if ($risk === 'NO') {
            return max(0.0, (float) config('services.snack_box.min_remaining_to_open_no', 5));
        }

        return 0.0;
    }

    public function activateDeviceForUser(int $userId, ?string $deviceId = null): SnackBoxDevice
    {
        $resolvedDeviceId = $this->resolveDeviceId($deviceId);

        return SnackBoxDevice::query()->updateOrCreate(
            ['device_id' => $resolvedDeviceId],
            [
                'active_user_id' => $userId,
                'last_activated_at' => now(),
            ]
        );
    }

    public function getStatusForUser(int $userId, ?string $deviceId = null): array
    {
        $resolvedDeviceId = $this->resolveDeviceId($deviceId);
        $device = SnackBoxDevice::query()->where('device_id', $resolvedDeviceId)->first();
        $todaySugar = $this->todaySugarByUser($userId);
        $latestPrediction = $this->latestPredictionByUser($userId);
        $risk = $this->normalizeRisk($latestPrediction?->result);
        $limit = $this->sugarLimitForRisk($risk);
        $reason = $this->statusReason($risk, $todaySugar, $limit);
        $remaining = $limit > 0 ? max($limit - $todaySugar, 0.0) : 0.0;

        return [
            'device_id' => $resolvedDeviceId,
            'active_user_id' => $device?->active_user_id,
            'is_active_user' => (int) ($device?->active_user_id ?? 0) === $userId,
            'risk_diabetes' => $risk,
            'sugar_limit' => round($limit, 2),
            'today_sugar' => round($todaySugar, 2),
            'remaining_sugar' => round($remaining, 2),
            'can_consume' => $reason === 'allowed',
            'can_open_servo' => $reason === 'allowed',
            'reason' => $reason,
            'message' => $this->reasonMessage($reason, $risk, $todaySugar, $limit),
            'last_health_check_id' => $latestPrediction?->check_id,
            'last_health_check_at' => $this->toIso8601($latestPrediction?->created_at),
        ];
    }

    public function ensureCanConsume(int $userId, float $additionalSugar): array
    {
        $status = $this->getStatusForUser($userId);
        $limit = (float) $status['sugar_limit'];
        $today = (float) $status['today_sugar'];
        $projected = $today + $additionalSugar;

        if (($status['reason'] ?? '') === 'health_check_required') {
            throw new RuntimeException('Anda harus melakukan Diabetes Check terlebih dahulu sebelum konsumsi produk.');
        }

        if (($status['reason'] ?? '') === 'sugar_limit_reached') {
            throw new RuntimeException('Kuota gula harian Anda sudah penuh. Produk tidak bisa dikonsumsi lagi hari ini.');
        }

        if (($status['reason'] ?? '') === 'remaining_too_small') {
            throw new RuntimeException((string) ($status['message'] ?? 'Sisa kuota gula terlalu kecil. Produk tidak bisa dikonsumsi lagi hari ini.'));
        }

        if ($projected > $limit) {
            throw new RuntimeException(
                'Produk ini akan melewati kuota gula harian Anda. Total saat ini '
                . round($today, 2) . 'g, tambahan ' . round($additionalSugar, 2)
                . 'g, batas ' . round($limit, 2) . 'g.'
            );
        }

        return $status + [
            'projected_sugar' => round($projected, 2),
            'projected_remaining' => round(max($limit - $projected, 0.0), 2),
        ];
    }

    public function buildServoDecision(?string $deviceId = null): array
    {
        $resolvedDeviceId = $this->resolveDeviceId($deviceId);
        $device = SnackBoxDevice::query()->where('device_id', $resolvedDeviceId)->first();

        if ($device === null || $device->active_user_id === null) {
            return $this->decisionPayload(
                deviceId: $resolvedDeviceId,
                allowOpen: false,
                reason: 'no_active_user'
            );
        }

        $status = $this->getStatusForUser((int) $device->active_user_id, $resolvedDeviceId);

        return $this->decisionPayload(
            deviceId: $resolvedDeviceId,
            allowOpen: (bool) $status['can_open_servo'],
            reason: (string) $status['reason'],
            status: $status,
            activeUserId: (int) $device->active_user_id
        );
    }

    private function decisionPayload(
        string $deviceId,
        bool $allowOpen,
        string $reason,
        ?array $status = null,
        ?int $activeUserId = null
    ): array {
        return [
            'device_id' => $deviceId,
            'allow_open' => $allowOpen,
            'reason' => $reason,
            'message' => $status['message'] ?? $this->reasonMessage($reason, 'UNKNOWN', 0, 0),
            'risk_diabetes' => $status['risk_diabetes'] ?? 'UNKNOWN',
            'sugar_limit' => (float) ($status['sugar_limit'] ?? 0),
            'today_sugar' => (float) ($status['today_sugar'] ?? 0),
            'remaining_sugar' => (float) ($status['remaining_sugar'] ?? 0),
            'active_user_id' => $activeUserId,
            'open_duration_ms' => $this->servoOpenDurationMs(),
            'decided_at' => now()->toIso8601String(),
        ];
    }

    private function latestPredictionByUser(int $userId): ?object
    {
        return DiabetesPrediction::query()
            ->select([
                'diabetes_predictions.result',
                'diabetes_predictions.check_id',
                'health_checks.created_at',
            ])
            ->join('health_checks', 'health_checks.id', '=', 'diabetes_predictions.check_id')
            ->where('health_checks.user_id', $userId)
            ->orderByDesc('health_checks.created_at')
            ->orderByDesc('health_checks.id')
            ->first();
    }

    private function todaySugarByUser(int $userId): float
    {
        return (float) DB::table('user_consumptions')
            ->where('user_id', $userId)
            ->where('date', getCurrentDate())
            ->sum('gr_sugar_consumed');
    }

    private function resolveDeviceId(?string $deviceId): string
    {
        $resolved = trim((string) ($deviceId ?? ''));
        if ($resolved !== '') {
            return $resolved;
        }

        return $this->defaultDeviceId();
    }

    private function normalizeRisk(?string $value): string
    {
        $normalized = strtolower(trim((string) $value));

        return match ($normalized) {
            'yes', 'ya' => 'YES',
            'no', 'tidak' => 'NO',
            default => 'UNKNOWN',
        };
    }

    private function sugarLimitForRisk(string $risk): float
    {
        return match ($risk) {
            'YES' => 10.0,
            'NO' => 25.0,
            default => 0.0,
        };
    }

    private function statusReason(string $risk, float $todaySugar, float $limit): string
    {
        if ($risk === 'UNKNOWN' || $limit <= 0) {
            return 'health_check_required';
        }

        if ($todaySugar >= $limit) {
            return 'sugar_limit_reached';
        }

        $remaining = max($limit - $todaySugar, 0.0);
        $minimumToOpen = $this->minRemainingToOpen($risk);
        if ($remaining <= $minimumToOpen) {
            return 'remaining_too_small';
        }

        return 'allowed';
    }

    private function reasonMessage(string $reason, string $risk, float $todaySugar, float $limit): string
    {
        return match ($reason) {
            'allowed' => 'Akses box diizinkan. Kuota gula masih tersedia.',
            'health_check_required' => 'Diabetes Check belum tersedia. Lakukan cek kesehatan terlebih dahulu.',
            'no_active_user' => 'Belum ada user aktif yang terhubung ke Smart Snack Box.',
            'sugar_limit_reached' => 'Kuota gula harian sudah penuh (' . round($todaySugar, 2) . 'g dari batas ' . round($limit, 2) . 'g).',
            'remaining_too_small' => 'Sisa kuota gula tinggal ' . round(max($limit - $todaySugar, 0), 2) . 'g. Box dikunci untuk mencegah konsumsi melebihi batas harian.',
            'sugar_limit_would_exceed' => 'Produk ini akan membuat kuota gula melebihi batas harian.',
            'backend_unavailable' => 'Backend tidak tersedia. Smart Snack Box tetap terkunci demi keamanan.',
            default => 'Status Smart Snack Box tidak diketahui.',
        };
    }

    private function toIso8601(mixed $value): ?string
    {
        if ($value === null || $value === '') {
            return null;
        }

        return \Carbon\Carbon::parse((string) $value)->toIso8601String();
    }
}
