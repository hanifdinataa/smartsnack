<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// Migration: buat tabel health_results
// Menggantikan diabetes_predictions untuk menyimpan hasil evaluasi
// status kesehatan tanpa machine learning (normal/perlu_perhatian per parameter).
return new class extends Migration {
    public function up(): void
    {
        Schema::create('health_results', function (Blueprint $table) {
            $table->id();
            $table->foreignId('check_id')->constrained('health_checks')->cascadeOnDelete();
            // Status per parameter
            $table->enum('heart_status', ['normal', 'perlu_perhatian'])->default('normal');
            $table->enum('temp_status',  ['normal', 'perlu_perhatian'])->default('normal');
            $table->enum('bmi_status',   ['normal', 'kurus', 'gemuk', 'obesitas'])->default('normal');
            // Status keseluruhan
            $table->enum('overall_status', ['normal', 'perlu_perhatian'])->default('normal');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('health_results');
    }
};
