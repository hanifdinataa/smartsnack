<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::table('user_barcode_scans', function (Blueprint $table) {
            $table->string('scan_source', 32)
                ->default('unknown')
                ->after('barcode');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('user_barcode_scans', function (Blueprint $table) {
            $table->dropColumn('scan_source');
        });
    }
};
