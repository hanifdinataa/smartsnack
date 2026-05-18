<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class DiabetesPrediction extends Model
{
    public $timestamps = false;

    protected $fillable = [
        'check_id',
        'result',
    ];
}
