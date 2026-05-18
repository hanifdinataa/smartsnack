<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('health_checks', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            $table->dateTime('created_at')->useCurrent();
        });

        Schema::create('heart_rates', function (Blueprint $table) {
            $table->id();
            $table->foreignId('check_id')->constrained('health_checks')->cascadeOnDelete();
            $table->integer('heart_rate');
        });

        Schema::create('body_temperatures', function (Blueprint $table) {
            $table->id();
            $table->foreignId('check_id')->constrained('health_checks')->cascadeOnDelete();
            $table->decimal('temperature', 5, 2);
        });

        Schema::create('body_metrics', function (Blueprint $table) {
            $table->id();
            $table->foreignId('check_id')->constrained('health_checks')->cascadeOnDelete();
            $table->decimal('height', 5, 2);
            $table->decimal('weight', 5, 2);
            $table->decimal('bmi', 5, 2);
        });

        Schema::create('diabetes_predictions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('check_id')->constrained('health_checks')->cascadeOnDelete();
            $table->string('result', 5);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('diabetes_predictions');
        Schema::dropIfExists('body_metrics');
        Schema::dropIfExists('body_temperatures');
        Schema::dropIfExists('heart_rates');
        Schema::dropIfExists('health_checks');
    }
};
