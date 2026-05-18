<?php

use Carbon\Carbon;

function getCurrentDate(): string
{
    return Carbon::now('Asia/Jakarta')->toDateString(); // Format: YYYY-MM-DD
}

function successResponse($data = null, $message = 'Success', $code = 200)
{
    return response()->json([
        'success' => true,
        'code'    => $code,
        'message' => $message,
        'data'    => $data,
    ], $code);
}


function  errorResponse($message = 'Error', $errors = null, $code = 400)
{
    return response()->json([
        'success' => false,
        'code'    => $code,
        'message' => $message,
        'errors'  => $errors,
    ], $code);
}

function sugarGrade(
    ?string $category,
    ?float $sugar,
    ?float $netWeight,
    ?float $servingSizeMl = null
): string
{
    $sugarValue = $sugar ?? 0.0;
    $netWeightValue = $netWeight ?? 0.0;

    if ($netWeightValue <= 0) {
        return '-';
    }

    // Multiple Traffic Light (MTL) threshold per 100 satuan:
    // Hijau < 2.5, Kuning 2.5 - 11.25, Merah > 11.25.
    $per100 = ($sugarValue / $netWeightValue) * 100;
    $lowThreshold = 2.5;
    $mediumThreshold = 11.25;

    if ($per100 < $lowThreshold) {
        return 'Hijau';
    }
    if ($per100 <= $mediumThreshold) {
        return 'Kuning';
    }
    return 'Merah';
}
