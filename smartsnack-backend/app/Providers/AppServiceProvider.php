<?php

namespace App\Providers;

use Illuminate\Console\Events\CommandStarting;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    private static bool $servoListenerBootstrapped = false;
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        if (app()->runningInConsole()) {
            // Fallback langsung untuk command `php artisan serve`
            // (beberapa environment tidak memicu CommandStarting sesuai ekspektasi).
            $argv = $_SERVER['argv'] ?? [];
            if (is_array($argv) && in_array('serve', $argv, true)) {
                $this->autoStartServoListenerForLocalServe();
            }

            Event::listen(CommandStarting::class, function (CommandStarting $event) {
                if ($event->command !== 'serve') {
                    return;
                }
                $this->autoStartServoListenerForLocalServe();
            });
        }
    }

    private function autoStartServoListenerForLocalServe(): void
    {
        if (self::$servoListenerBootstrapped) {
            return;
        }

        if (!app()->runningInConsole()) {
            return;
        }

        if (!filter_var((string) env('AUTO_START_SERVO_LISTENER', true), FILTER_VALIDATE_BOOL)) {
            return;
        }

        self::$servoListenerBootstrapped = true;

        $artisan = base_path('artisan');
        $php = PHP_BINARY ?: 'php';
        $logFile = storage_path('logs/servo-listener.log');

        if (DIRECTORY_SEPARATOR === '\\') {
            // Gunakan `NUL` untuk menghindari konflik file handle log saat spawn ulang.
            $command = 'cmd /c start "" /B "' . $php . '" "' . $artisan . '" snackbox:listen-servo > NUL 2>&1';
            @pclose(@popen($command, 'r'));
        } else {
            $command = '"' . $php . '" "' . $artisan . '" snackbox:listen-servo';
            @exec($command . ' > /dev/null 2>&1 &');
        }
    }
}
