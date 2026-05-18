<?php

namespace App\Services;

use App\Models\Product;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;

class ImageClassificationService
{
    /**
     * Cache hash gambar produk agar tidak fetch ulang berkali-kali pada satu request.
     *
     * @var array<string, string|null>
     */
    private array $imageHashCache = [];

    /**
     * Klasifikasi gambar produk.
     *
     * Prioritas:
     * 1) Endpoint XGBoost eksternal (jika dikonfigurasi)
     * 2) Fallback average-hash image matching (agar web tetap bisa dipakai)
     */
    public function classifyImage(UploadedFile $image): array
    {
        $fromXgboost = $this->classifyWithXgboostEndpoint($image);
        if ($fromXgboost !== null) {
            return $fromXgboost;
        }

        $fromHashMatching = $this->classifyWithImageHashMatching($image);
        if ($fromHashMatching !== null) {
            return $fromHashMatching;
        }

        return [
            'predicted_product_id' => null,
            'confidence' => 0.0,
            'algorithm' => 'none',
        ];
    }

    private function classifyWithXgboostEndpoint(UploadedFile $image): ?array
    {
        $endpoint = config('services.xgboost_classifier.endpoint');
        if (empty($endpoint)) {
            return null;
        }

        try {
            $realPath = $image->getRealPath();
            if ($realPath === false || !is_file($realPath)) {
                return null;
            }

            $binary = file_get_contents($realPath);
            if ($binary === false) {
                return null;
            }

            $response = Http::timeout(25)
                ->acceptJson()
                ->attach('image', $binary, $image->getClientOriginalName())
                ->post($endpoint);

            if (!$response->successful()) {
                Log::warning('XGBoost endpoint returned non-success response', [
                    'status' => $response->status(),
                    'body' => $response->body(),
                ]);
                return null;
            }

            $json = $response->json();
            $predictedId = $json['predicted_product_id'] ?? $json['product_id'] ?? null;
            if (!is_numeric($predictedId)) {
                return null;
            }

            $predictedId = (int) $predictedId;
            $exists = Product::query()->whereKey($predictedId)->exists();
            if (!$exists) {
                return null;
            }

            $confidence = $json['confidence'] ?? null;
            $confidenceValue = is_numeric($confidence) ? round((float) $confidence, 4) : null;

            return [
                'predicted_product_id' => $predictedId,
                'confidence' => $confidenceValue,
                'algorithm' => 'xgboost_service',
            ];
        } catch (\Throwable $e) {
            Log::warning('XGBoost endpoint classification failed', [
                'message' => $e->getMessage(),
            ]);
            return null;
        }
    }

    private function classifyWithImageHashMatching(UploadedFile $image): ?array
    {
        $realPath = $image->getRealPath();
        if ($realPath === false || !is_file($realPath)) {
            return null;
        }

        $binary = file_get_contents($realPath);
        if ($binary === false) {
            return null;
        }

        $inputHash = $this->averageHashFromBinary($binary);
        if ($inputHash === null) {
            return null;
        }

        $products = Product::query()
            ->select(['id', 'image'])
            ->whereNotNull('image')
            ->get();

        $bestProductId = null;
        $bestDistance = PHP_INT_MAX;
        $hashedCandidates = 0;

        foreach ($products as $product) {
            if (empty($product->image)) {
                continue;
            }

            $productHash = $this->resolveProductImageHash((string) $product->image);
            if ($productHash === null) {
                continue;
            }
            $hashedCandidates++;

            $distance = $this->hammingDistance($inputHash, $productHash);
            if ($distance < $bestDistance) {
                $bestDistance = $distance;
                $bestProductId = (int) $product->id;
            }
        }

        if ($bestProductId === null) {
            Log::info('Image hash classifier found no comparable product images', [
                'total_products' => $products->count(),
                'hashed_candidates' => $hashedCandidates,
            ]);
            return null;
        }

        // Threshold dibuat lebih toleran agar foto kemasan dengan sudut/crop berbeda
        // tetap bisa dikenali sebagai produk yang sama.
        if ($bestDistance > 30) {
            Log::info('Image hash classifier rejected by distance threshold', [
                'best_product_id' => $bestProductId,
                'best_distance' => $bestDistance,
                'hashed_candidates' => $hashedCandidates,
                'threshold' => 30,
            ]);
            return null;
        }

        $confidence = max(0.0, 1.0 - ($bestDistance / 64.0));

        return [
            'predicted_product_id' => $bestProductId,
            'confidence' => round($confidence, 4),
            'algorithm' => 'image_hash_fallback',
            'distance' => $bestDistance,
        ];
    }

    private function resolveProductImageHash(string $imageSource): ?string
    {
        if (array_key_exists($imageSource, $this->imageHashCache)) {
            return $this->imageHashCache[$imageSource];
        }

        $binary = null;

        if (Str::startsWith($imageSource, ['http://', 'https://'])) {
            $urlPath = parse_url($imageSource, PHP_URL_PATH);
            if (is_string($urlPath) && $urlPath !== '') {
                $localPath = $this->resolveLocalImagePath($urlPath);
                if ($localPath !== null && is_file($localPath)) {
                    $content = file_get_contents($localPath);
                    if ($content !== false) {
                        $binary = $content;
                    }
                }
            }

            try {
                if ($binary === null) {
                    $response = Http::timeout(20)->get($imageSource);
                    if ($response->successful()) {
                        $binary = $response->body();
                    }
                }
            } catch (\Throwable $e) {
                Log::debug('Failed to fetch product image URL for hashing', [
                    'image' => $imageSource,
                    'message' => $e->getMessage(),
                ]);
            }
        } else {
            $localPath = $this->resolveLocalImagePath($imageSource);
            if ($localPath !== null && is_file($localPath)) {
                $content = file_get_contents($localPath);
                if ($content !== false) {
                    $binary = $content;
                }
            }
        }

        $hash = $binary ? $this->averageHashFromBinary($binary) : null;
        $this->imageHashCache[$imageSource] = $hash;

        return $hash;
    }

    private function resolveLocalImagePath(string $imageSource): ?string
    {
        $normalized = ltrim(str_replace('\\', '/', $imageSource), '/');
        $withoutStoragePrefix = preg_replace('/^storage\//', '', $normalized) ?? $normalized;

        $candidates = [
            public_path($normalized),
            public_path('storage/' . $withoutStoragePrefix),
            storage_path('app/public/' . $normalized),
            storage_path('app/public/' . $withoutStoragePrefix),
        ];

        foreach ($candidates as $path) {
            if (is_file($path)) {
                return $path;
            }
        }

        return null;
    }

    private function averageHashFromBinary(string $binary): ?string
    {
        if (!function_exists('imagecreatefromstring')) {
            return null;
        }

        $img = @imagecreatefromstring($binary);
        if ($img === false) {
            return null;
        }

        $resized = imagecreatetruecolor(8, 8);
        imagecopyresampled($resized, $img, 0, 0, 0, 0, 8, 8, imagesx($img), imagesy($img));

        $values = [];
        for ($y = 0; $y < 8; $y++) {
            for ($x = 0; $x < 8; $x++) {
                $rgb = imagecolorat($resized, $x, $y);
                $r = ($rgb >> 16) & 0xFF;
                $g = ($rgb >> 8) & 0xFF;
                $b = $rgb & 0xFF;
                $gray = (int) round(($r + $g + $b) / 3);
                $values[] = $gray;
            }
        }

        imagedestroy($resized);
        imagedestroy($img);

        if (count($values) !== 64) {
            return null;
        }

        $avg = array_sum($values) / 64;
        $bits = '';
        foreach ($values as $value) {
            $bits .= ($value >= $avg) ? '1' : '0';
        }

        return $bits;
    }

    private function hammingDistance(string $hashA, string $hashB): int
    {
        $length = min(strlen($hashA), strlen($hashB));
        $distance = 0;

        for ($i = 0; $i < $length; $i++) {
            if ($hashA[$i] !== $hashB[$i]) {
                $distance++;
            }
        }

        return $distance + abs(strlen($hashA) - strlen($hashB));
    }
}
