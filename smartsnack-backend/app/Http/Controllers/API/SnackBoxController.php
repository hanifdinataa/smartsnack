<?php

namespace App\Http\Controllers\API;

use App\Http\Controllers\Controller;
use App\Services\SnackBoxAccessService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Throwable;

class SnackBoxController extends Controller
{
    public function __construct(private readonly SnackBoxAccessService $service)
    {
    }






    // Alur fungsi ini: request dari app diproses di controller (validasi + service/model/database), lalu response dikirim balik ke aplikasi.
    public function activate(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'device_id' => 'nullable|string|max:100',
        ]);

        try {
            $device = $this->service->activateDeviceForUser(
                userId: (int) $request->user()->id,
                deviceId: $validated['device_id'] ?? null
            );

            $status = $this->service->getStatusForUser(
                userId: (int) $request->user()->id,
                deviceId: $device->device_id
            );

            return successResponse($status, 'Smart Snack Box berhasil diaktifkan untuk user ini.');
        } catch (Throwable $e) {
            return errorResponse($e->getMessage(), null, 422);
        }
    }






    // Alur fungsi ini: request dari app diproses di controller (validasi + service/model/database), lalu response dikirim balik ke aplikasi.
    public function status(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'device_id' => 'nullable|string|max:100',
        ]);

        try {
            $status = $this->service->getStatusForUser(
                userId: (int) $request->user()->id,
                deviceId: $validated['device_id'] ?? null
            );

            return successResponse($status, 'Status Smart Snack Box berhasil diambil.');
        } catch (Throwable $e) {
            return errorResponse($e->getMessage(), null, 422);
        }
    }
}


