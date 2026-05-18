<?php

namespace App\Http\Controllers\API;

use App\Http\Controllers\Controller;
use App\Services\ImageClassificationService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ImageClassificationController extends Controller
{
    public function __construct(private readonly ImageClassificationService $imageClassificationService)
    {
    }

    // Alur fungsi ini: app upload gambar produk, backend validasi file lalu kirim ke service klasifikasi, hasil prediksi dikirim balik sebagai JSON.
    public function classify(Request $request): JsonResponse
    {
        $request->validate([
            'image' => ['required', 'image', 'max:5120'],
        ]);

        $result = $this->imageClassificationService->classifyImage($request->file('image'));

        if (empty($result['predicted_product_id'])) {
            return errorResponse(
                'Produk tidak terdeteksi dari gambar. Silakan pilih produk secara manual.',
                [
                    'algorithm' => $result['algorithm'] ?? 'none',
                ],
                422
            );
        }

        return successResponse($result, 'Product classified successfully.');
    }
}
