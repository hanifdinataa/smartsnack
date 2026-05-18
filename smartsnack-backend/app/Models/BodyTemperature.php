<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class BodyTemperature extends Model
{
    public $timestamps = false;

    protected $fillable = [
        'check_id',
        'temperature',
    ];
}
