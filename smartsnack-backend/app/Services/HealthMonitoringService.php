<?php

namespace App\Services;

use App\Models\SensorRawReading;
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
        // Simpan indeks pembacaan real-time untuk grafik Flutter
        $readingIndex = 0;

        $response = $this->sendMqttCommandAndWait(
            checkId: $checkId,
            userId: $userId,
            action: 'heart_rate',
            timeoutSeconds: max(90, $this->mqttTimeoutSeconds()),
            rawCallback: static function (array $msg) use ($checkId, &$readingIndex): void {
                if (($msg['action'] ?? '') !== 'heart_rate_raw') {
                    return;
                }
                $bpm = (float) ($msg['bpm'] ?? 0);
                if ($bpm <= 10 || $bpm > 250) {
                    return;
                }
                try {
                    SensorRawReading::create([
                        'check_id'      => $checkId,
                        'sensor_type'   => 'heart_rate',
                        'value'         => round($bpm, 1),
                        'reading_index' => $readingIndex++,
                        'recorded_at'   => now(),
                    ]);
                } catch (\Throwable) {
                    // Jangan gagalkan pengukuran jika pencatatan raw gagal
                }
            }
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
        // Simpan indeks pembacaan real-time untuk grafik Flutter
        $readingIndex = 0;

        $response = $this->sendMqttCommandAndWait(
            checkId: $checkId,
            userId: $userId,
            action: 'body_temperature',
            timeoutSeconds: min(45, $this->mqttTimeoutSeconds()),
            rawCallback: static function (array $msg) use ($checkId, &$readingIndex): void {
                if (($msg['action'] ?? '') !== 'body_temp_raw') {
                    return;
                }
                $temp = (float) ($msg['temp'] ?? 0);
                if ($temp <= 20 || $temp > 50) {
                    return;
                }
                try {
                    SensorRawReading::create([
                        'check_id'      => $checkId,
                        'sensor_type'   => 'body_temp',
                        'value'         => round($temp, 2),
                        'reading_index' => $readingIndex++,
                        'recorded_at'   => now(),
                    ]);
                } catch (\Throwable) {
                    // Jangan gagalkan pengukuran jika pencatatan raw gagal
                }
            }
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

    // Evaluasi status kesehatan berdasarkan standar referensi:
    // 1. Detak Jantung: Siloam Hospitals / Kemenkes RI (1-10 thn: 70-120 bpm, 11-17+ thn: 60-100 bpm)
    // 2. Suhu Tubuh: AAP (Normal: 36.4-37.5 °C, Demam: >= 38.0 °C)
    // 3. BMI: FAO (<18.5 Underweight, 18.5-24.9 Normal, 25-29.9 Pre-obese, 30-34.9 Obese I, 35-39.9 Obese II, >=40 Obese III)
    // Evaluasi status kesehatan berdasarkan standar referensi:
    // 1. Detak Jantung: Siloam Hospitals / Kemenkes RI (1-10 thn: 70-120 bpm, 11-17+ thn: 60-100 bpm)
    // 2. Suhu Tubuh: AAP (Normal: 36.4-37.5 °C, Demam: >= 38.0 °C)
    // 3. BMI Anak (5-19 thn): Standar WHO 2007 BMI-for-age Z-scores (Severe Thinness < -3SD, Thinness < -2SD, Normal -2SD s/d +1SD, Overweight > +1SD, Obese > +2SD)
    // 4. BMI Dewasa (>19 thn): WHO Adult (<18.5 Underweight, 18.5-24.9 Normal, 25-29.9 Pre-obese, >=30 Obese)
    public function evaluateHealthStatus(array $payload): array
    {
        $heartRate = (float) ($payload['heart_rate'] ?? 0);
        $bodyTemp  = (float) ($payload['body_temp']  ?? 0);
        $bmi       = (float) ($payload['bmi']        ?? 0);
        $age       = (int)   ($payload['age']         ?? 10);
        $gender    = (string)($payload['gender']      ?? 'Male');

        // ─ Detak Jantung (Siloam Hospitals / Kemenkes RI) ─
        if ($age <= 10) {
            if ($heartRate < 70) {
                $heartStatus = 'rendah';
            } elseif ($heartRate > 120) {
                $heartStatus = 'tinggi';
            } else {
                $heartStatus = 'normal';
            }
        } else {
            if ($heartRate < 60) {
                $heartStatus = 'rendah';
            } elseif ($heartRate > 100) {
                $heartStatus = 'tinggi';
            } else {
                $heartStatus = 'normal';
            }
        }

        // ─ Suhu Tubuh (AAP) ─
        if ($bodyTemp < 36.4) {
            $tempStatus = 'rendah';
        } elseif ($bodyTemp <= 37.5) {
            $tempStatus = 'normal';
        } elseif ($bodyTemp < 38.0) {
            $tempStatus = 'hangat';
        } else {
            $tempStatus = 'demam';
        }

        // ─ Status Gizi / BMI (WHO 2007 untuk anak 5-19 tahun, WHO Dewasa untuk >19 tahun) ─
        $bmiStatus = $this->classifyBmiWho2007($bmi, $age, $gender);

        // ─ Status Keseluruhan ─
        $isBmiNormal = in_array($bmiStatus, ['normal', 'gizi_baik'], true);
        $allNormal = ($heartStatus === 'normal') && ($tempStatus === 'normal') && $isBmiNormal;
        $overallStatus = $allNormal ? 'normal' : 'perlu_perhatian';

        return [
            'heart_status'   => $heartStatus,
            'temp_status'    => $tempStatus,
            'bmi_status'     => $bmiStatus,
            'overall_status' => $overallStatus,
        ];
    }

    // Klasifikasi status gizi / BMI berbasis WHO 2007 BMI-for-age Z-Score Table
    private function classifyBmiWho2007(float $bmi, int $age, string $gender): string
    {
        if ($bmi <= 0) {
            return 'normal';
        }

        // WHO 2007 BMI-for-age Z-scores cutoffs table [ -3SD, -2SD, +1SD, +2SD ]
        // Boys (Laki-laki) usia 5-19 tahun
        $whoBoys = [
            5  => [12.1, 13.0, 16.6, 18.3],
            6  => [12.1, 13.0, 16.8, 18.5],
            7  => [12.3, 13.1, 17.0, 19.0],
            8  => [12.4, 13.3, 17.4, 19.7],
            9  => [12.6, 13.5, 17.9, 20.5],
            10 => [12.8, 13.7, 18.5, 21.4],
            11 => [13.1, 14.1, 19.2, 22.5],
            12 => [13.4, 14.5, 19.9, 23.6],
            13 => [13.8, 14.9, 20.8, 24.8],
            14 => [14.3, 15.5, 21.8, 25.9],
            15 => [14.7, 16.0, 22.7, 27.0],
            16 => [15.1, 16.5, 23.5, 27.9],
            17 => [15.4, 16.9, 24.3, 28.6],
            18 => [15.7, 17.3, 24.9, 29.2],
            19 => [15.9, 17.6, 25.4, 29.7],
        ];

        // Girls (Perempuan) usia 5-19 tahun
        $whoGirls = [
            5  => [11.8, 12.7, 16.8, 18.8],
            6  => [11.7, 12.7, 17.0, 19.2],
            7  => [11.8, 12.7, 17.3, 19.8],
            8  => [11.9, 12.9, 17.7, 20.6],
            9  => [12.1, 13.1, 18.3, 21.5],
            10 => [12.4, 13.5, 19.0, 22.6],
            11 => [12.7, 13.9, 19.9, 23.7],
            12 => [13.2, 14.4, 20.8, 25.0],
            13 => [13.6, 14.9, 21.8, 26.2],
            14 => [14.0, 15.4, 22.7, 27.3],
            15 => [14.4, 15.9, 23.5, 28.2],
            16 => [14.6, 16.2, 24.1, 28.9],
            17 => [14.7, 16.4, 24.5, 29.3],
            18 => [14.7, 16.4, 24.8, 29.5],
            19 => [14.7, 16.5, 25.0, 29.7],
        ];

        if ($age >= 5 && $age <= 19) {
            $table = (strcasecmp($gender, 'Female') === 0 || strcasecmp($gender, 'Perempuan') === 0)
                ? $whoGirls
                : $whoBoys;

            $cutoffs = $table[$age] ?? $table[10];
            $sd_neg3 = $cutoffs[0];
            $sd_neg2 = $cutoffs[1];
            $sd_pos1 = $cutoffs[2];
            $sd_pos2 = $cutoffs[3];

            if ($bmi < $sd_neg3) {
                return 'gizi_buruk';
            } elseif ($bmi < $sd_neg2) {
                return 'gizi_kurang';
            } elseif ($bmi <= $sd_pos1) {
                return 'gizi_baik';
            } elseif ($bmi <= $sd_pos2) {
                return 'gizi_lebih';
            } else {
                return 'obesitas';
            }
        }

        // Dewasa (>19 tahun) - Klasifikasi WHO Dewasa
        if ($bmi < 18.5) {
            return 'underweight';
        } elseif ($bmi <= 24.9) {
            return 'normal';
        } elseif ($bmi <= 29.9) {
            return 'pre_obese';
        } else {
            return 'obesitas';
        }
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

    /**
     * Kirim perintah MQTT ke sensor dan tunggu hasilnya.
     * Jika $rawCallback diberikan, backend juga subscribe ke rawTopic
     * dan memanggil callback tiap kali ada data mentah masuk (untuk grafik real-time).
     */
    private function sendMqttCommandAndWait(
        int $checkId,
        int $userId,
        string $action,
        int $timeoutSeconds,
        ?callable $rawCallback = null
    ): array {
        $deviceId     = $this->mqttDeviceId();
        $commandTopic = "smartsnack/health/command/{$deviceId}";
        $resultTopic  = "smartsnack/health/result/{$deviceId}";
        $rawTopic     = "smartsnack/health/raw/{$deviceId}";

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

            // Juga subscribe ke raw topic jika ada callback (untuk grafik real-time)
            if ($rawCallback !== null) {
                $client->subscribe($rawTopic);
            }

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

            $matcher = static function (array $message) use ($checkId): bool {
                return (int) ($message['check_id'] ?? 0) === $checkId;
            };

            // Gunakan method yang mendengarkan dua topik sekaligus jika ada rawCallback
            $response = $rawCallback !== null
                ? $client->waitForPayloadWithSideEffect(
                    primaryTopic: $resultTopic,
                    timeoutSeconds: $timeoutSeconds,
                    matcher: $matcher,
                    rawTopic: $rawTopic,
                    rawCallback: $rawCallback
                )
                : $client->waitForPayload(
                    topic: $resultTopic,
                    timeoutSeconds: $timeoutSeconds,
                    matcher: $matcher
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
