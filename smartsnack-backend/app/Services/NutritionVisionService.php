<?php

namespace App\Services;

use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Http;

class NutritionVisionService
{
    private function endpoint(): string
    {
        return rtrim((string) config('services.label_gizi_service.endpoint', 'http://127.0.0.1:5060'), '/');
    }

    private function timeout(): int
    {
        return max(30, (int) config('services.label_gizi_service.timeout', 120));
    }

    public function detectFromImage(UploadedFile $image): array
    {
        try {
            $response = Http::timeout($this->timeout())
                ->attach(
                    'image',
                    file_get_contents($image->getRealPath()),
                    $image->getClientOriginalName() ?: 'nutrition.jpg'
                )
                ->post($this->endpoint() . '/detect-nutrition-label');

            if (!$response->successful()) {
                $message = (string) ($response->json('message') ?? 'Service AI label gizi gagal merespons.');
                throw new \Exception($message);
            }

            $data = $response->json('data');
            if (!is_array($data)) {
                throw new \Exception('Hasil analisis label gizi kosong.');
            }

            return $data;
        } catch (\Throwable $e) {
            throw new \Exception(
                'Service AI label gizi belum aktif. Jalankan label-gizi-service lalu coba lagi. Detail: ' .
                $e->getMessage()
            );
        }
    }

    public function detectBarcodeFromImage(UploadedFile $image): array
    {
        try {
            $response = Http::timeout($this->timeout())
                ->attach(
                    'image',
                    file_get_contents($image->getRealPath()),
                    $image->getClientOriginalName() ?: 'barcode.jpg'
                )
                ->post($this->endpoint() . '/detect-barcode');

            if (!$response->successful()) {
                $message = (string) ($response->json('message') ?? 'Service AI barcode gagal merespons.');
                throw new \Exception($message);
            }

            $data = $response->json('data');
            if (!is_array($data)) {
                throw new \Exception('Hasil analisis barcode kosong.');
            }

            return $data;
        } catch (\Throwable $e) {
            throw new \Exception(
                'Service AI barcode belum aktif. Jalankan label-gizi-service lalu coba lagi. Detail: ' .
                $e->getMessage()
            );
        }
    }

    public function detectProductPackageFromImage(UploadedFile $image): array
    {
        // Fokus sistem saat ini: label gizi.
        // Endpoint lama kemasan dipertahankan agar backward compatible, tetapi diarahkan ke deteksi label gizi.
        return $this->detectFromImage($image);
    }
}
