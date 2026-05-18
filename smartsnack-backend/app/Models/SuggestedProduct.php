<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class SuggestedProduct extends Model
{
    protected $fillable = [
        'user_id',
        'name',
        'category',
        'image',
        'gr_sugar_content',
        'net_weight',
        'servings_per_package',
        'serving_size_ml',
    ];

    public function user()
    {
        return $this->belongsTo(User::class);
    }
}
