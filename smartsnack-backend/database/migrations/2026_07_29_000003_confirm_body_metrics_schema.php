<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

// Migration: tambah kolom weight (berat badan) dan height (tinggi badan) ke body_metrics
// untuk menyimpan hasil pembacaan sensor LoadCell dan HC-SR04.
// Kolom height dan weight sudah ada dari migration sebelumnya (2026_04_18),
// jadi kita tambah yang belum ada saja. Juga tambah kolom height_cm dan weight_kg
// sebagai alias decimal lebih presisi (5,2 sudah ada, tapi rename ke kolom yang sama).
// Sebenarnya kolom sudah ada (height, weight) — migration ini untuk menambahkan
// kolom baru jika diperlukan (misal: height_source, weight_source).
// Skema sudah cukup: height decimal(5,2) dan weight decimal(5,2) sudah ada.
// Migration ini kita pakai untuk memastikan ada kolom bmi yang cukup presisi.
return new class extends Migration {
    public function up(): void
    {
        // Tidak ada perubahan skema tambahan yang diperlukan untuk body_metrics.
        // Height, weight, bmi sudah ada dari migration 2026_04_18.
        // Age dan gender di body_metrics sudah ada dari migration 2026_04_21.
        // Kolom age dan gender di users (migration 2026_07_29_000001) sudah cukup.
    }

    public function down(): void
    {
        // nothing
    }
};
