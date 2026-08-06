<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Model untuk menyimpan data mentah (raw) dari sensor selama proses pengukuran.
 * Digunakan untuk menggambar grafik real-time di Flutter.
 *
 * @property int    $id
 * @property int    $check_id
 * @property string $sensor_type  ('heart_rate' atau 'body_temp')
 * @property float  $value
 * @property int    $reading_index
 * @property string $recorded_at
 */
class SensorRawReading extends Model
{
    public $timestamps = false;

    protected $table = 'sensor_raw_readings';

    protected $fillable = [
        'check_id',
        'sensor_type',
        'value',
        'reading_index',
        'recorded_at',
    ];

    protected $casts = [
        'check_id'      => 'integer',
        'value'         => 'float',
        'reading_index' => 'integer',
    ];
}
