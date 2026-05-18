<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class UserBarcodeScan extends Model
{
    protected $fillable = [
        'user_id',
        'product_id',
        'barcode',
        'scan_source',
        'scanned_at',
    ];

    public $timestamps = true;
}
