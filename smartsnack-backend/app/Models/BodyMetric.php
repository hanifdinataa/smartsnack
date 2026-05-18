<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class BodyMetric extends Model
{
    public $timestamps = false;

    protected $fillable = [
        'check_id',
        'age',
        'gender',
        'height',
        'weight',
        'bmi',
    ];
}
