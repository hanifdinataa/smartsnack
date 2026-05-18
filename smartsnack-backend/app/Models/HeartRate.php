<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class HeartRate extends Model
{
    public $timestamps = false;

    protected $fillable = [
        'check_id',
        'heart_rate',
    ];
}
