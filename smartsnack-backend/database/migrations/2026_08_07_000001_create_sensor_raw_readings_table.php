<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// Migration ini membuat tabel sensor_raw_readings untuk menyimpan
// data mentah sensor (detak jantung & suhu) secara real-time selama pengukuran.
// Data ini dipakai untuk menggambar grafik real-time di aplikasi Flutter.
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('sensor_raw_readings', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('check_id');
            $table->string('sensor_type', 30); // 'heart_rate' atau 'body_temp'
            $table->float('value');
            $table->unsignedInteger('reading_index')->default(0);
            $table->timestamp('recorded_at')->useCurrent();

            $table->index(['check_id', 'sensor_type', 'reading_index']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('sensor_raw_readings');
    }
};
