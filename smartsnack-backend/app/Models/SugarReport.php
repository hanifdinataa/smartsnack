<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class SugarReport extends Model
{
    protected $fillable = [
        'user_id',
        'week_number',
        'month',
        'year',
        'report'
    ];
}
