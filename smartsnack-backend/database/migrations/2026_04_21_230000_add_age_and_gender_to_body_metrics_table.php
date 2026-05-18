<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::table('body_metrics', function (Blueprint $table) {
            if (!Schema::hasColumn('body_metrics', 'age')) {
                $table->unsignedTinyInteger('age')->nullable()->after('check_id');
            }
            if (!Schema::hasColumn('body_metrics', 'gender')) {
                $table->enum('gender', ['Male', 'Female'])->nullable()->after('age');
            }
        });
    }

    public function down(): void
    {
        Schema::table('body_metrics', function (Blueprint $table) {
            if (Schema::hasColumn('body_metrics', 'gender')) {
                $table->dropColumn('gender');
            }
            if (Schema::hasColumn('body_metrics', 'age')) {
                $table->dropColumn('age');
            }
        });
    }
};
