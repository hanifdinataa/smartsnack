<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;
use RuntimeException;

class HealthMonitoringService
{
    private function mqttHost(): string
    {
        return trim((string) config('services.mqtt.host', '127.0.0.1'));
    }

    private function mqttPort(): int
    {
        return (int) config('services.mqtt.port', 1883);
    }

    private function mqttUsername(): ?string
    {
        $value = trim((string) config('services.mqtt.username', ''));
        return $value === '' ? null : $value;
    }

    private function mqttPassword(): ?string
    {
        $value = trim((string) config('services.mqtt.password', ''));
        return $value === '' ? null : $value;
    }

    private function mqttDeviceId(): string
    {
        return trim((string) config('services.mqtt.device_id', 'esp32_health_01'));
    }

    private function mqttClientPrefix(): string
    {
        return trim((string) config('services.mqtt.client_id_prefix', 'smartsnack_backend'));
    }

    private function mqttTimeoutSeconds(): int
    {
        return max(5, (int) config('services.mqtt.timeout_seconds', 120));
    }

    private function xgboostEndpoint(): string
    {
        return trim((string) config('services.diabetes_xgboost.endpoint', ''));
    }

    private function requireXgboostModel(): bool
    {
        return (bool) config('services.diabetes_xgboost.require_model', true);
    }

    public function fetchHeartRate(int $checkId, int $userId): array
    {
        $response = $this->sendMqttCommandAndWait(
            checkId: $checkId,
            userId: $userId,
            action: 'heart_rate',
            timeoutSeconds: max(90, $this->mqttTimeoutSeconds())
        );

        $value = $this->toFloat($response['heart_rate'] ?? null);
        if ($value === null || $value <= 0) {
            throw new RuntimeException('Detak jantung tidak terbaca. Pastikan jari menempel di sensor selama proses 1 menit.');
        }
        if ($value < 45 || $value > 180) {
            throw new RuntimeException('Detak jantung tidak valid (' . round($value) . ' bpm). Ulangi pengukuran dan pastikan jari stabil menutup sensor.');
        }

        return [
            'value' => $value,
            'source' => 'mqtt',
            'transport' => 'mqtt',
            'device_id' => $this->mqttDeviceId(),
        ];
    }

    public function fetchBodyTemperature(int $checkId, int $userId): array
    {
        $response = $this->sendMqttCommandAndWait(
            checkId: $checkId,
            userId: $userId,
            action: 'body_temperature',
            timeoutSeconds: min(45, $this->mqttTimeoutSeconds())
        );

        $value = $this->toFloat($response['body_temp'] ?? null);
        if ($value === null) {
            throw new RuntimeException('Suhu tubuh tidak terbaca. Pastikan posisi dahi sudah tepat di sensor.');
        }

        return [
            'value' => $value,
            'source' => 'mqtt',
            'transport' => 'mqtt',
            'device_id' => $this->mqttDeviceId(),
        ];
    }

    private function sendMqttCommandAndWait(int $checkId, int $userId, string $action, int $timeoutSeconds): array
    {
        $deviceId = $this->mqttDeviceId();
        $commandTopic = "smartsnack/health/command/{$deviceId}";
        $resultTopic = "smartsnack/health/result/{$deviceId}";

        $client = new SimpleMqttClient(
            host: $this->mqttHost(),
            port: $this->mqttPort(),
            clientId: $this->mqttClientPrefix() . '_' . uniqid(),
            username: $this->mqttUsername(),
            password: $this->mqttPassword()
        );

        try {
            $client->connect(10);
            $client->subscribe($resultTopic);

            $commandPayload = json_encode([
                'action' => $action,
                'check_id' => $checkId,
                'user_id' => $userId,
                'requested_at' => now()->toIso8601String(),
            ], JSON_UNESCAPED_SLASHES);

            if ($commandPayload === false) {
                throw new RuntimeException('Gagal menyusun payload command MQTT.');
            }

            $client->publish($commandTopic, $commandPayload);

            $response = $client->waitForPayload(
                topic: $resultTopic,
                timeoutSeconds: $timeoutSeconds,
                matcher: static function (array $message) use ($checkId): bool {
                    return (int) ($message['check_id'] ?? 0) === $checkId;
                }
            );

            if ($response === null) {
                throw new RuntimeException('Perangkat tidak merespons dalam batas waktu.');
            }

            $status = strtolower((string) ($response['status'] ?? ''));
            if ($status !== 'ok') {
                $error = (string) ($response['error'] ?? 'unknown_error');
                if ($error === 'finger_not_detected') {
                    throw new RuntimeException('Jari belum terdeteksi. Tempelkan jari menutup sensor MAX30102 dengan stabil sampai pengukuran selesai.');
                }
                if ($error === 'signal_invalid') {
                    throw new RuntimeException('Sinyal detak tidak stabil. Coba ulang dan kurangi gerakan jari saat pengukuran.');
                }
                if ($error === 'sensor_unavailable') {
                    throw new RuntimeException('Sensor tidak tersedia. Cek koneksi kabel dan catu daya perangkat.');
                }
                throw new RuntimeException("Perangkat mengembalikan error: {$error}");
            }

            return $response;
        } finally {
            $client->disconnect();
        }
    }

    public function analyzeRisk(array $payload): array
    {
        $endpoint = $this->xgboostEndpoint();
        if ($endpoint === '') {
            if ($this->requireXgboostModel()) {
                throw new RuntimeException('Service XGBoost belum diaktifkan. Jalankan XGBOOST/main.py dalam mode API lalu isi DIABETES_XGBOOST_ENDPOINT di .env backend.');
            }
            throw new RuntimeException('Service XGBoost endpoint kosong.');
        }

        $requestPayload = $payload;
        $requestPayload['gender'] = $requestPayload['gender'] ?? 'Male';

        try {
            $resp = Http::timeout(20)->post($endpoint, $requestPayload);
        } catch (\Throwable $e) {
            throw new RuntimeException('Service XGBoost tidak dapat dihubungi. Pastikan XGBOOST/main.py berjalan sebagai API.');
        }

        if (!$resp->successful()) {
            throw new RuntimeException('Service XGBoost merespons gagal (HTTP ' . $resp->status() . ').');
        }

        $data = $resp->json();
        if (!is_array($data)) {
            throw new RuntimeException('Response XGBoost tidak valid.');
        }

        $probabilityDiabetes = $this->extractProbabilityDiabetes($data);
        $rawRisk = strtoupper((string) ($data['risk'] ?? $data['risk_diabetes'] ?? $data['result'] ?? ''));
        if (in_array($rawRisk, ['YA', 'YES'], true)) {
            return [
                'risk' => 'yes',
                'algorithm' => 'xgboost_service',
                'risk_percent' => $probabilityDiabetes === null ? null : round($probabilityDiabetes * 100, 2),
            ];
        }
        if (in_array($rawRisk, ['TIDAK', 'NO'], true)) {
            return [
                'risk' => 'no',
                'algorithm' => 'xgboost_service',
                'risk_percent' => $probabilityDiabetes === null ? null : round($probabilityDiabetes * 100, 2),
            ];
        }
        throw new RuntimeException('Response XGBoost tidak memiliki label risiko yang valid.');
    }

    private function extractProbabilityDiabetes(array $data): ?float
    {
        $candidates = [
            $data['probability_diabetes'] ?? null,
            $data['probability'] ?? null,
            $data['score'] ?? null,
            $data['risk_probability'] ?? null,
        ];

        foreach ($candidates as $candidate) {
            $value = $this->toFloat($candidate);
            if ($value === null) {
                continue;
            }

            if ($value > 1 && $value <= 100) {
                $value = $value / 100;
            }

            if ($value >= 0 && $value <= 1) {
                return $value;
            }
        }

        return null;
    }

    private function toFloat($value): ?float
    {
        if ($value === null || $value === '') return null;
        if (is_numeric($value)) return (float) $value;
        return null;
    }
}
