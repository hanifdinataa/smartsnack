<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class UserConsumption extends Model
{
    protected $fillable = [
        'user_id',
        'product_id',
        'sugar_report_id',
        'date',
        'sugar_grade',
        'percentage_consumed',
        'gr_sugar_consumed'
    ];

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function product()
    {
        return $this->belongsTo(Product::class);
    }
}
