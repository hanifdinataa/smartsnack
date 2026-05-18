<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use App\Repositories\ProductRepository;

class ProductService
{
    protected $productRepo;

    public function __construct(ProductRepository $productRepo)
    {
        $this->productRepo = $productRepo;
    }

    public function searchByName(string $keyword)
    {
        $products = $this->productRepo->searchByName($keyword);

        if (!$products) {
            throw new \Exception('Produk tidak ditemukan.');
        }

        foreach ($products as $product) {
            $product->sugar_grade = sugarGrade(
                $product->category,
                $product->gr_sugar_content,
                $product->net_weight
            );

            $product->gr_sugar_content = (float) $product->gr_sugar_content;
            $product->net_weight = (float) $product->net_weight;

            $product->makeHidden([
                'category',
            ]);
        }

        return $products;
    }

    public function findBestByLabel(string $label, ?string $category = null)
    {
        $normalizedTarget = $this->normalizeProductName($label);
        if ($normalizedTarget === '') {
            throw new \Exception('Label produk wajib diisi.');
        }

        $products = $this->productRepo->getAllForLabelMatching();
        $bestProduct = null;
        $bestScore = PHP_INT_MIN;
        $targetTokens = $this->tokenizeNormalizedName($normalizedTarget);

        foreach ($products as $product) {
            if ($category !== null && $category !== '' && $product->category !== $category) {
                continue;
            }

            $candidateName = $this->normalizeProductName((string) ($product->name ?? ''));
            if ($candidateName === '') {
                continue;
            }

            if ($candidateName === $normalizedTarget) {
                return $this->hydrateProductForApi($product);
            }

            $score = 0;

            $candidateTokens = $this->tokenizeNormalizedName($candidateName);
            $overlapCount = count(array_intersect($targetTokens, $candidateTokens));
            $score += ($overlapCount * 20);
            $score -= abs(count($targetTokens) - count($candidateTokens)) * 2;

            if (
                $overlapCount >= 2 &&
                (str_contains($candidateName, $normalizedTarget) || str_contains($normalizedTarget, $candidateName))
            ) {
                $score += 25;
            }

            if ($score > $bestScore) {
                $bestScore = $score;
                $bestProduct = $product;
            }
        }

        // Tolak match lemah agar foto random tidak "dipaksa" cocok.
        if ($bestProduct !== null && $bestScore >= 40) {
            return $this->hydrateProductForApi($bestProduct);
        }

        throw new \Exception('Produk dengan label tersebut tidak ditemukan.');
    }

    public function allWithVarians()
    {
        return $this->productRepo->allWithVarians();
    }

    public function getAll()
    {
        $products = $this->productRepo->allWithVarians();

        if (!$products) {
            throw new \Exception('Produk tidak ditemukan.');
        }

        foreach ($products as $product) {
            $product->sugar_grade = sugarGrade(
                $product->category,
                $product->gr_sugar_content,
                $product->net_weight
            );

            $product->gr_sugar_content = (float) $product->gr_sugar_content;
            $product->net_weight = (float) $product->net_weight;
            $product->makeHidden(['created_at', 'updated_at']);
        }

        return $products;
    }

    public function create(array $data)
    {
        return $this->productRepo->create($data);
    }

    public function findOrCreateFromNutritionLabel(array $data): array
    {
        $name = trim((string) ($data['name'] ?? ''));
        $category = (string) ($data['category'] ?? 'food');
        $grSugarContent = (float) ($data['gr_sugar_content'] ?? 0);
        $netWeight = (float) ($data['net_weight'] ?? 0);
        $image = $this->normalizeNullableString($data['image'] ?? '');

        $matched = $this->findBestMatchByLabelData($name, $category, $grSugarContent);
        if ($matched) {
            $updatedMatched = $this->productRepo->update($matched, [
                'name' => $name !== '' ? $name : (string) ($matched->name ?? ''),
                'category' => $category !== '' ? $category : (string) ($matched->category ?? 'food'),
                'image' => $image !== '' ? $image : (string) ($matched->image ?? ''),
                'gr_sugar_content' => $grSugarContent,
                'net_weight' => $netWeight,
            ]);

            return [
                'product' => $this->hydrateProductForApi($updatedMatched),
                'created' => false,
            ];
        }

        $product = $this->productRepo->create([
            'name' => $name,
            'category' => $category,
            'image' => $image,
            'gr_sugar_content' => $grSugarContent,
            'net_weight' => $netWeight,
        ]);

        return [
            'product' => $this->hydrateProductForApi($product),
            'created' => true,
        ];
    }

    public function update($product, array $data)
    {
        return $this->productRepo->update($product, $data);
    }

    public function delete($product)
    {
        return $this->productRepo->delete($product);
    }

    public function findProductById($id)
    {
        $product = $this->productRepo->findProductById($id);

        if (!$product) {
            throw new \Exception('Produk tidak ditemukan.');
        }

        $product->sugar_grade = sugarGrade(
            $product->category,
            $product->gr_sugar_content,
            $product->net_weight
        );

        $product->gr_sugar_content = (float) $product->gr_sugar_content;
        $product->net_weight = (float) $product->net_weight;

        return $product;
    }

    public function findProductByBarcode(string $barcode)
    {
        $normalizedBarcode = $this->normalizeBarcode($barcode);
        if ($normalizedBarcode === '') {
            throw new \Exception('Barcode wajib diisi.');
        }

        $fallbackProduct = null;
        foreach ($this->barcodeCandidates($normalizedBarcode) as $candidate) {
            $product = $this->productRepo->findByBarcode($candidate);
            if ($product) {
                if ($this->isFallbackBarcodeProduct($product)) {
                    $fallbackProduct = $product;
                    continue;
                }
                return $this->hydrateProductForApi($product);
            }
        }

        if ($this->shouldUseExternalBarcodeLookup()) {
            foreach ($this->barcodeCandidates($normalizedBarcode) as $candidate) {
                $externalProduct = $this->fetchExternalProductByBarcode($candidate);
                if ($externalProduct !== null) {
                    return $this->hydrateProductForApi($externalProduct);
                }
            }
        }

        if ($fallbackProduct !== null) {
            return $this->hydrateProductForApi($fallbackProduct);
        }

        $createdFallbackProduct = $this->createFallbackProductByBarcode($normalizedBarcode);
        return $createdFallbackProduct ? $this->hydrateProductForApi($createdFallbackProduct) : null;
    }

    public function findLocalProductByBarcode(string $barcode)
    {
        $normalizedBarcode = $this->normalizeBarcode($barcode);
        if ($normalizedBarcode === '') {
            return null;
        }

        foreach ($this->barcodeCandidates($normalizedBarcode) as $candidate) {
            $product = $this->productRepo->findByBarcode($candidate);
            if ($product) {
                return $this->hydrateProductForApi($product);
            }
        }

        return null;
    }

    public function findLocalProductRawByBarcode(string $barcode)
    {
        $normalizedBarcode = $this->normalizeBarcode($barcode);
        if ($normalizedBarcode === '') {
            return null;
        }

        foreach ($this->barcodeCandidates($normalizedBarcode) as $candidate) {
            $product = $this->productRepo->findByBarcode($candidate);
            if ($product) {
                return $product;
            }
        }

        return null;
    }

    private function hydrateProductForApi($product)
    {
        $product->sugar_grade = sugarGrade(
            $product->category,
            $product->gr_sugar_content !== null ? (float) $product->gr_sugar_content : null,
            $product->net_weight !== null ? (float) $product->net_weight : null
        );

        $product->gr_sugar_content = (float) ($product->gr_sugar_content ?? 0);
        $product->net_weight = (float) ($product->net_weight ?? 0);

        return $product;
    }

    private function findBestMatchByLabelData(
        string $name,
        ?string $category,
        ?float $grSugarContent
    ) {
        $normalizedTarget = $this->normalizeProductName($name);
        if ($normalizedTarget === '') {
            return null;
        }

        $products = $this->productRepo->getAllForLabelMatching();

        foreach ($products as $product) {
            if ($category !== null && $category !== '' && $product->category !== $category) {
                continue;
            }

            $candidateName = $this->normalizeProductName((string) ($product->name ?? ''));
            if ($candidateName === '') {
                continue;
            }

            if ($candidateName === $normalizedTarget) {
                return $product;
            }
        }
        return null;
    }

    private function normalizeProductName(string $name): string
    {
        $normalized = mb_strtolower($name, 'UTF-8');
        $normalized = preg_replace('/[^\pL\pN]+/u', ' ', $normalized) ?? '';
        return trim(preg_replace('/\s+/', ' ', $normalized) ?? '');
    }

    private function tokenizeNormalizedName(string $normalizedName): array
    {
        if ($normalizedName === '') {
            return [];
        }
        return array_values(array_filter(
            explode(' ', $normalizedName),
            static fn (string $token) => mb_strlen($token, 'UTF-8') >= 3
        ));
    }

    private function normalizeNullableString($value): string
    {
        $text = trim((string) $value);
        if ($text === '' || strtolower($text) === 'null' || strtolower($text) === 'undefined') {
            return '';
        }
        return $text;
    }

    private function normalizeBarcode(string $barcode): string
    {
        return preg_replace('/\D+/', '', $barcode) ?? '';
    }

    private function barcodeCandidates(string $normalizedBarcode): array
    {
        $candidates = [$normalizedBarcode];

        if (strlen($normalizedBarcode) === 12) {
            $checkDigit = $this->calculateEan13CheckDigit($normalizedBarcode);
            if ($checkDigit !== '') {
                $candidates[] = $normalizedBarcode . $checkDigit;
            }
            $candidates[] = '0' . $normalizedBarcode;
        }

        if (strlen($normalizedBarcode) === 13 && str_starts_with($normalizedBarcode, '0')) {
            $candidates[] = substr($normalizedBarcode, 1);
        }

        if (strlen($normalizedBarcode) === 14 && str_starts_with($normalizedBarcode, '0')) {
            $candidates[] = substr($normalizedBarcode, 1);
        }

        if (strlen($normalizedBarcode) > 14) {
            $candidates[] = substr($normalizedBarcode, 0, 14);
            $candidates[] = substr($normalizedBarcode, 0, 13);
            $candidates[] = substr($normalizedBarcode, 0, 12);
        }

        return array_values(array_unique($candidates));
    }

    private function shouldUseExternalBarcodeLookup(): bool
    {
        if (app()->environment('local')) {
            return true;
        }
        return (bool) config('services.open_food_facts.enabled', true);
    }

    private function calculateEan13CheckDigit(string $payload12): string
    {
        if (strlen($payload12) !== 12 || preg_match('/\D/', $payload12)) {
            return '';
        }

        $sum = 0;
        for ($i = 0; $i < 12; $i++) {
            $digit = (int) $payload12[$i];
            $sum += ($i % 2 === 0) ? $digit : ($digit * 3);
        }

        return (string) ((10 - ($sum % 10)) % 10);
    }

    private function fetchExternalProductByBarcode(string $normalizedBarcode)
    {
        $fields = implode(',', [
            'product_name',
            'generic_name',
            'categories',
            'categories_tags',
            'nutriments',
            'image_front_url',
            'image_url',
            'serving_quantity',
            'serving_size',
            'quantity',
            'product_quantity',
        ]);
        $endpoint = "https://world.openfoodfacts.org/api/v2/product/{$normalizedBarcode}.json?" . http_build_query([
            'fields' => $fields,
        ]);

        try {
            $timeout = max(15, (int) config('services.open_food_facts.timeout', 8));
            $response = Http::retry(2, 400)
                ->timeout($timeout)
                ->acceptJson()
                ->withHeaders([
                    'User-Agent' => 'SugarCare/1.0 (barcode lookup)',
                ])
                ->get($endpoint);
            if (!$response->successful()) {
                return null;
            }

            $json = $response->json();
            if (($json['status'] ?? 0) !== 1) {
                return null;
            }

            $rawProduct = $json['product'] ?? null;
            if (!is_array($rawProduct)) {
                return null;
            }

            $nutriments = is_array($rawProduct['nutriments'] ?? null) ? $rawProduct['nutriments'] : [];
            $sugar100g = $nutriments['sugars_100g']
                ?? $nutriments['sugars_100ml']
                ?? $nutriments['sugars']
                ?? $nutriments['sugars_value']
                ?? null;

            $servingQuantity = $rawProduct['serving_quantity'] ?? null;
            if (!is_numeric($servingQuantity)) {
                $servingText = strtolower((string) ($rawProduct['serving_size'] ?? ''));
                if (preg_match('/(\d+(?:[.,]\d+)?)/', $servingText, $matches) === 1) {
                    $servingQuantity = (float) str_replace(',', '.', $matches[1]);
                }
            }

            if (!is_numeric($sugar100g)) {
                $sugarServing = $nutriments['sugars_serving'] ?? null;
                if (is_numeric($sugarServing) && is_numeric($servingQuantity) && (float) $servingQuantity > 0) {
                    $sugar100g = ((float) $sugarServing / (float) $servingQuantity) * 100;
                }
            }

            if (!is_numeric($sugar100g)) {
                $sugar100g = 0.0;
            }
            $sugar100g = max(0, (float) $sugar100g);

            $name = trim((string) ($rawProduct['product_name'] ?? $rawProduct['generic_name'] ?? ''));
            if ($name === '') {
                $name = 'Produk Barcode ' . $normalizedBarcode;
            }

            $image = (string) ($rawProduct['image_front_url'] ?? $rawProduct['image_url'] ?? '');
            $categorySource = strtolower(
                trim((string) ($rawProduct['categories'] ?? '')) . ' ' .
                trim((string) ($rawProduct['categories_tags'][0] ?? '')) . ' ' .
                trim((string) ($rawProduct['product_name'] ?? ''))
            );
            $isDrink = str_contains($categorySource, 'drink') ||
                str_contains($categorySource, 'beverage') ||
                str_contains($categorySource, 'minuman') ||
                str_contains($categorySource, 'juice') ||
                str_contains($categorySource, 'tea') ||
                str_contains($categorySource, 'coffee') ||
                str_contains($categorySource, 'soda');
            $category = $isDrink ? 'drink' : 'food';

            $netWeight = $rawProduct['product_quantity'] ?? null;
            if (!is_numeric($netWeight)) {
                $quantityText = strtolower((string) ($rawProduct['quantity'] ?? ''));
                if (preg_match('/(\d+(?:[.,]\d+)?)/', $quantityText, $matches) === 1) {
                    $netWeight = (float) str_replace(',', '.', $matches[1]);
                }
            }
            if (!is_numeric($netWeight) || (float) $netWeight <= 0) {
                $netWeight = 100.0;
            }

            $payload = [
                'name' => $name,
                'barcode' => $normalizedBarcode,
                'category' => $category,
                'image' => $image,
                'gr_sugar_content' => round($sugar100g, 2),
                'net_weight' => (float) $netWeight,
            ];

            $existing = $this->productRepo->findByBarcode($normalizedBarcode);
            if ($existing) {
                if ($this->isFallbackBarcodeProduct($existing)) {
                    return $this->productRepo->update($existing, $payload);
                }
                return $existing;
            }

            return $this->productRepo->create($payload);
        } catch (\Throwable $e) {
            Log::warning('External barcode lookup failed', [
                'barcode' => $normalizedBarcode,
                'message' => $e->getMessage(),
            ]);
            return null;
        }
    }

    private function createFallbackProductByBarcode(string $normalizedBarcode)
    {
        $existing = $this->productRepo->findByBarcode($normalizedBarcode);
        if ($existing) {
            return $existing;
        }

        try {
            return $this->productRepo->create([
                'name' => 'Produk Barcode ' . $normalizedBarcode,
                'barcode' => $normalizedBarcode,
                'category' => 'food',
                'image' => '',
                'gr_sugar_content' => 0,
                'net_weight' => 100,
            ]);
        } catch (\Throwable $e) {
            Log::warning('Fallback barcode product creation failed', [
                'barcode' => $normalizedBarcode,
                'message' => $e->getMessage(),
            ]);
            return null;
        }
    }

    private function isFallbackBarcodeProduct($product): bool
    {
        $name = strtolower(trim((string) ($product->name ?? '')));
        $sugar = (float) ($product->gr_sugar_content ?? 0);

        if (str_starts_with($name, 'produk barcode')) {
            return true;
        }

        return $sugar <= 0.0 && $name === '';
    }

    public function findProductCategoryById(int $id)
    {
        return $this->productRepo->findProductCategoryById($id);
    }

    public function findSugarProductById(int $id)
    {
        return $this->productRepo->findSugarProductById($id);
    }

    public function findNetWeightById(int $id)
    {
        return $this->productRepo->findNetWeightById($id);
    }

    
    public function findProductNameById(int $id)
    {
        return $this->productRepo->findProductNameById($id);
    }

    public function getProductImgById(int $id)
    {
        return $this->productRepo->getProductImgById($id);
    }

    public function getDetailProduk(int $id)
    {
        $product = $this->productRepo->findByIdWithVarians($id);

        if (!$product) {
            throw new \Exception('Produk tidak ditemukan.');
        }

        $product->sugar_grade = sugarGrade(
            $product->category,
            $product->gr_sugar_content,
            $product->net_weight
        );

        $product->gr_sugar_content = (float) $product->gr_sugar_content;
        $product->net_weight = (float) $product->net_weight;

        return $product;
    }

    public function getSameVarianProduct(string $category, int $excludeId)
    {
        return $this->productRepo->getSameVarianProduct($category, $excludeId);
    }
    
    
}
