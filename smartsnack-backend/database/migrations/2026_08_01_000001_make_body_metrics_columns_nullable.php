<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::table('body_metrics', function (Blueprint $table) {
            $table->decimal('height', 5, 2)->nullable()->default(0)->change();
            $table->decimal('weight', 5, 2)->nullable()->default(0)->change();
            $table->decimal('bmi', 5, 2)->nullable()->default(0)->change();
        });
    }

    public function down(): void
    {
        Schema::table('body_metrics', function (Blueprint $table) {
            $table->decimal('height', 5, 2)->change();
            $table->decimal('weight', 5, 2)->change();
            $table->decimal('bmi', 5, 2)->change();
        });
    }
};
