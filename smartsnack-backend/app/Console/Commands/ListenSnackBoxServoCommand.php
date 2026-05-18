<?php

namespace App\Console\Commands;

use App\Services\SnackBoxAccessService;
use Illuminate\Console\Command;
use PhpMqtt\Client\ConnectionSettings;
use PhpMqtt\Client\MqttClient;
use Throwable;

class ListenSnackBoxServoCommand extends Command
{
    protected $signature = 'snackbox:listen-servo';

    protected $description = 'Listen push-button events from Smart Snack Box and publish servo decisions.';

    public function handle(SnackBoxAccessService $service): int
    {
        $host = trim((string) config('services.mqtt.host', '127.0.0.1'));
        $port = (int) config('services.mqtt.port', 1883);
        $username = trim((string) config('services.mqtt.username', ''));
        $password = trim((string) config('services.mqtt.password', ''));
        $clientPrefix = trim((string) config('services.mqtt.client_id_prefix', 'smartsnack_backend'));

        $settings = (new ConnectionSettings())
            ->setConnectTimeout(5)
            ->setSocketTimeout(5)
            ->setKeepAliveInterval(10);

        if ($username !== '') {
            $settings = $settings->setUsername($username);
        }

        if ($password !== '') {
            $settings = $settings->setPassword($password);
        }

        while (true) {
            try {
                $clientId = $clientPrefix . '_servo_' . uniqid();
                $mqtt = new MqttClient($host, $port, $clientId);
                $mqtt->connect($settings, true);

                $this->info('MQTT servo listener connected to ' . $host . ':' . $port);

                $mqtt->subscribe('smartsnack/box/event/+', function (string $topic, string $message) use ($mqtt, $service) {
                    $parts = explode('/', $topic);
                    $topicDeviceId = trim((string) end($parts));

                    try {
                        $payload = json_decode($message, true);
                        if (!is_array($payload)) {
                            throw new \RuntimeException('Invalid JSON payload: ' . $message);
                        }

                        $deviceId = trim((string) ($payload['device_id'] ?? ''));
                        if ($deviceId === '') {
                            $deviceId = $topicDeviceId;
                        }

                        $event = trim((string) ($payload['event'] ?? ''));
                        if ($event !== 'button_pressed') {
                            $this->line('Ignored event for device ' . $deviceId . ': ' . $event);
                            return;
                        }

                        $decision = $service->buildServoDecision($deviceId);
                        $mqtt->publish(
                            'smartsnack/box/decision/' . $deviceId,
                            json_encode($decision, JSON_UNESCAPED_SLASHES),
                            0
                        );

                        $this->line('Decision published for device ' . $deviceId . ': ' . ($decision['reason'] ?? 'unknown'));
                    } catch (Throwable $callbackError) {
                        $deviceId = $topicDeviceId !== '' ? $topicDeviceId : trim((string) config('services.snack_box.device_id', 'esp32_health_01'));
                        $fallbackDecision = [
                            'device_id' => $deviceId,
                            'allow_open' => false,
                            'reason' => 'backend_unavailable',
                            'risk_diabetes' => 'unknown',
                            'sugar_limit' => 0,
                            'today_sugar' => 0,
                            'remaining_sugar' => 0,
                            'open_duration_ms' => (int) config('services.snack_box.servo_open_duration_ms', 3000),
                            'message' => 'Backend listener error',
                        ];

                        $mqtt->publish(
                            'smartsnack/box/decision/' . $deviceId,
                            json_encode($fallbackDecision, JSON_UNESCAPED_SLASHES),
                            0
                        );

                        $this->error('Callback error for device ' . $deviceId . ': ' . $callbackError->getMessage());
                    }
                }, 0);

                $mqtt->loop(true);
            } catch (Throwable $e) {
                $this->error('Servo listener error: ' . $e->getMessage());
                sleep(2);
            }
        }
    }
}
