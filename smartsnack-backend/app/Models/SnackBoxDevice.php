<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class SnackBoxDevice extends Model
{
    protected $fillable = [
        'device_id',
        'active_user_id',
        'last_activated_at',
    ];

    protected $casts = [
        'last_activated_at' => 'datetime',
    ];

    public function activeUser()
    {
        return $this->belongsTo(User::class, 'active_user_id');
    }
}
