<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('snack_box_devices', function (Blueprint $table) {
            $table->id();
            $table->string('device_id')->unique();
            $table->foreignId('active_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->dateTime('last_activated_at')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('snack_box_devices');
    }
};
