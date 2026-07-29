<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class HealthResult extends Model
{
    protected $fillable = [
        'check_id',
        'heart_status',
        'temp_status',
        'bmi_status',
        'overall_status',
    ];

    public function healthCheck()
    {
        return $this->belongsTo(HealthCheck::class, 'check_id');
    }
}
