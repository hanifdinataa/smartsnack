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
        Schema::table('user_consumptions', function (Blueprint $table) {
            $table->unsignedBigInteger('sugar_report_id')->after('product_id');
            $table->foreign('sugar_report_id')->references('id')->on('sugar_reports')->onDelete('cascade');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('user_consumptions', function (Blueprint $table) {
            $table->dropForeign(['sugar_report_id']);
            $table->dropColumn('sugar_report_id');
        });
    }
};
