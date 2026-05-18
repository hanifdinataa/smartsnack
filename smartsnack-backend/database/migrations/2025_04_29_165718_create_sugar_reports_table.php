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
        Schema::create('sugar_reports', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')
                ->constrained()
                ->onDelete('cascade');
            $table->integer('week_number')->notNull();
            $table->string('month', 20)->notNull();
            $table->integer('year')->notNull();
            $table->string('report', 255)->notNull();
            $table->timestamps();

            $table->index(['month', 'year'], 'idx_sugar_report');
            $table->unique(['user_id', 'week_number', 'month', 'year']);
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('sugar_reports');
    }
};
