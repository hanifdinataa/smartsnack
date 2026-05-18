<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('products', function (Blueprint $table) {
            if (Schema::hasColumn('products', 'information')) {
                $table->dropColumn('information');
            }
            if (Schema::hasColumn('products', 'servings_per_package')) {
                $table->dropColumn('servings_per_package');
            }
            if (Schema::hasColumn('products', 'serving_size_ml')) {
                $table->dropColumn('serving_size_ml');
            }
        });

        Schema::dropIfExists('product_varians');
        Schema::dropIfExists('varians');
    }

    public function down(): void
    {
        Schema::table('products', function (Blueprint $table) {
            if (!Schema::hasColumn('products', 'information')) {
                $table->text('information')->nullable()->after('image');
            }
            if (!Schema::hasColumn('products', 'servings_per_package')) {
                $table->decimal('servings_per_package', 8, 2)->default(1)->after('net_weight');
            }
            if (!Schema::hasColumn('products', 'serving_size_ml')) {
                $table->decimal('serving_size_ml', 8, 2)->nullable()->after('servings_per_package');
            }
        });

        if (!Schema::hasTable('varians')) {
            Schema::create('varians', function (Blueprint $table) {
                $table->id();
                $table->string('name');
                $table->timestamps();
            });
        }

        if (!Schema::hasTable('product_varians')) {
            Schema::create('product_varians', function (Blueprint $table) {
                $table->id();
                $table->foreignId('product_id')->constrained('products')->cascadeOnDelete();
                $table->foreignId('varian_id')->constrained('varians')->cascadeOnDelete();
                $table->timestamps();
            });
        }
    }
};
