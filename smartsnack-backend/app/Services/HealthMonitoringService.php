<?php

namespace App\Services;

use RuntimeException;

// Service ini menangani semua logika monitoring kesehatan:
// - Fetch data sensor (detak jantung, suhu, berat badan, tinggi badan) via MQTT
// - Evaluasi status kesehatan (normal/perlu_perhatian) tanpa machine learning
// - Publish perintah buka servo ke MQTT setelah cek kesehatan berhasil
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

    // ─── FETCH SENSOR DATA VIA MQTT ────────────────────────────────────────

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
            'value'     => $value,
            'source'    => 'mqtt',
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
            'value'     => $value,
            'source'    => 'mqtt',
            'transport' => 'mqtt',
            'device_id' => $this->mqttDeviceId(),
        ];
    }

    // Fetch berat badan dari sensor LoadCell (HX711) via MQTT command "weight"
    public function fetchWeight(int $checkId, int $userId): array
    {
        $response = $this->sendMqttCommandAndWait(
            checkId: $checkId,
            userId: $userId,
            action: 'weight',
            timeoutSeconds: 30
        );

        $value = $this->toFloat($response['weight_kg'] ?? null);
        if ($value === null || $value < 0) {
            throw new RuntimeException('Berat badan tidak terbaca. Pastikan berdiri di atas timbangan dengan stabil.');
        }
        if ($value > 200) {
            throw new RuntimeException('Berat badan tidak valid (' . round($value, 1) . ' kg). Ulangi pengukuran.');
        }

        return [
            'value'     => $value,
            'source'    => 'mqtt',
            'transport' => 'mqtt',
            'device_id' => $this->mqttDeviceId(),
        ];
    }

    // Fetch tinggi badan dari sensor HC-SR04 via MQTT command "height"
    public function fetchHeight(int $checkId, int $userId): array
    {
        $response = $this->sendMqttCommandAndWait(
            checkId: $checkId,
            userId: $userId,
            action: 'height',
            timeoutSeconds: 30
        );

        $value = $this->toFloat($response['height_cm'] ?? null);
        if ($value === null || $value <= 0) {
            throw new RuntimeException('Tinggi badan tidak terbaca. Pastikan berdiri tegak di bawah sensor ultrasonik.');
        }
        if ($value < 50 || $value > 250) {
            throw new RuntimeException('Tinggi badan tidak valid (' . round($value, 1) . ' cm). Ulangi pengukuran.');
        }

        return [
            'value'     => $value,
            'source'    => 'mqtt',
            'transport' => 'mqtt',
            'device_id' => $this->mqttDeviceId(),
        ];
    }

    // ─── EVALUASI STATUS KESEHATAN (tanpa machine learning) ────────────────

    // Evaluasi status kesehatan berdasarkan nilai sensor.
    // Mengembalikan array berisi status per parameter dan status keseluruhan.
    public function evaluateHealthStatus(array $payload): array
    {
        $heartRate = (float) ($payload['heart_rate'] ?? 0);
        $bodyTemp  = (float) ($payload['body_temp']  ?? 0);
        $bmi       = (float) ($payload['bmi']        ?? 0);
        $age       = (int)   ($payload['age']         ?? 10);

        // ─ Detak Jantung ─
        // Nilai normal untuk anak: 70-110 bpm, dewasa: 60-100 bpm
        // Pakai rentang 60-110 sebagai adaptif untuk anak-anak
        if ($age <= 12) {
            $heartNormal = ($heartRate >= 70 && $heartRate <= 110);
        } else {
            $heartNormal = ($heartRate >= 60 && $heartRate <= 100);
        }
        $heartStatus = $heartNormal ? 'normal' : 'perlu_perhatian';

        // ─ Suhu Tubuh ─
        // Normal: 36.0 – 37.5 °C
        $tempNormal = ($bodyTemp >= 36.0 && $bodyTemp <= 37.5);
        $tempStatus = $tempNormal ? 'normal' : 'perlu_perhatian';

        // ─ BMI (WHO) ─
        if ($bmi <= 0) {
            $bmiStatus = 'normal'; // tidak ada data BMI, anggap normal
        } elseif ($bmi < 18.5) {
            $bmiStatus = 'kurus';
        } elseif ($bmi < 25.0) {
            $bmiStatus = 'normal';
        } elseif ($bmi < 30.0) {
            $bmiStatus = 'gemuk';
        } else {
            $bmiStatus = 'obesitas';
        }

        // ─ Status Keseluruhan ─
        $bmiNormal = in_array($bmiStatus, ['normal'], true);
        $allNormal = $heartNormal && $tempNormal && $bmiNormal;
        $overallStatus = $allNormal ? 'normal' : 'perlu_perhatian';

        return [
            'heart_status'   => $heartStatus,
            'temp_status'    => $tempStatus,
            'bmi_status'     => $bmiStatus,
            'overall_status' => $overallStatus,
        ];
    }

    // ─── MQTT: BUKA SERVO BOX ──────────────────────────────────────────────

    // Publish perintah buka servo ke ESP32 via MQTT.
    // Dipanggil setelah proses cek kesehatan berhasil — box otomatis terbuka
    // sebagai hadiah, dan akan menutup sendiri setelah 10 detik (di firmware).
    public function publishOpenBox(): bool
    {
        $deviceId  = $this->mqttDeviceId();
        $openTopic = "smartsnack/box/open/{$deviceId}";

        $payload = json_encode([
            'event'      => 'open_after_health_check',
            'device_id'  => $deviceId,
            'duration_ms' => 10000,
            'sent_at'    => now()->toIso8601String(),
        ], JSON_UNESCAPED_SLASHES);

        if ($payload === false) {
            return false;
        }

        $client = new SimpleMqttClient(
            host:     $this->mqttHost(),
            port:     $this->mqttPort(),
            clientId: $this->mqttClientPrefix() . '_open_' . uniqid(),
            username: $this->mqttUsername(),
            password: $this->mqttPassword()
        );

        try {
            $client->connect(10);
            $sent = $client->publish($openTopic, $payload);
            return $sent;
        } catch (\Throwable) {
            return false;
        } finally {
            $client->disconnect();
        }
    }

    // ─── MQTT INTERNAL ─────────────────────────────────────────────────────

    private function sendMqttCommandAndWait(int $checkId, int $userId, string $action, int $timeoutSeconds): array
    {
        $deviceId     = $this->mqttDeviceId();
        $commandTopic = "smartsnack/health/command/{$deviceId}";
        $resultTopic  = "smartsnack/health/result/{$deviceId}";

        $client = new SimpleMqttClient(
            host:     $this->mqttHost(),
            port:     $this->mqttPort(),
            clientId: $this->mqttClientPrefix() . '_' . uniqid(),
            username: $this->mqttUsername(),
            password: $this->mqttPassword()
        );

        try {
            $client->connect(10);
            $client->subscribe($resultTopic);

            $commandPayload = json_encode([
                'action'       => $action,
                'check_id'     => $checkId,
                'user_id'      => $userId,
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
                    throw new RuntimeException('Sinyal tidak stabil. Coba ulang dan kurangi gerakan saat pengukuran.');
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

    private function toFloat($value): ?float
    {
        if ($value === null || $value === '') return null;
        if (is_numeric($value)) return (float) $value;
        return null;
    }
}
