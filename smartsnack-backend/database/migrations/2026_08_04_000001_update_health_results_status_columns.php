<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration {
    public function up(): void
    {
        DB::statement("ALTER TABLE health_results MODIFY heart_status VARCHAR(50) NOT NULL DEFAULT 'normal'");
        DB::statement("ALTER TABLE health_results MODIFY temp_status VARCHAR(50) NOT NULL DEFAULT 'normal'");
        DB::statement("ALTER TABLE health_results MODIFY bmi_status VARCHAR(50) NOT NULL DEFAULT 'normal'");
    }

    public function down(): void
    {
    }
};
