<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasColumn('products', 'barcode')) {
            Schema::table('products', function (Blueprint $table) {
                $table->dropUnique('products_barcode_unique');
                $table->dropColumn('barcode');
            });
        }

        Schema::dropIfExists('user_barcode_scans');
    }

    public function down(): void
    {
        if (!Schema::hasColumn('products', 'barcode')) {
            Schema::table('products', function (Blueprint $table) {
                $table->string('barcode', 64)->nullable()->unique()->after('name');
            });
        }

        if (!Schema::hasTable('user_barcode_scans')) {
            Schema::create('user_barcode_scans', function (Blueprint $table) {
                $table->id();
                $table->foreignId('user_id')->constrained()->cascadeOnDelete();
                $table->foreignId('product_id')->constrained()->cascadeOnDelete();
                $table->string('barcode', 64);
                $table->string('scan_source', 32)->default('unknown');
                $table->timestamp('scanned_at')->nullable();
                $table->timestamps();
            });
        }
    }
};
