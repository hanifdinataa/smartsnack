<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Product extends Model
{
    protected $fillable = [
        'name',
        'category',
        'image',
        'gr_sugar_content',
        'net_weight',
        'serving_size',
    ];
}
