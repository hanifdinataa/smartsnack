<?php

namespace App\Http\Controllers\API;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Services\ProductService;
use App\Services\NutritionVisionService;
use App\Services\UserBarcodeScanService;
use Illuminate\Http\JsonResponse;
use App\Http\Resources\RecProductResource;
use Illuminate\Support\Facades\Storage;

class ProductController extends Controller
{
    protected $productService;
    protected $nutritionVisionService;
    protected $userBarcodeScanService;



    public function __construct(
        ProductService $productService,
        NutritionVisionService $nutritionVisionService,
        UserBarcodeScanService $userBarcodeScanService
    )
    {
        $this->productService = $productService;
        $this->nutritionVisionService = $nutritionVisionService;
        $this->userBarcodeScanService = $userBarcodeScanService;
    }

    private function barcodeProductPayload($product, string $barcode, ?string $scanSource = null): array
    {
        $netWeight = (float) ($product->net_weight ?? 0);
        $sugarGram = (float) ($product->gr_sugar_content ?? 0);
        $name = (string) ($product->name ?? '');
        $isFallbackData = str_starts_with(strtolower(trim($name)), 'produk barcode');

        return [
            'barcode' => $barcode,
            'scan_source' => $scanSource ?? '',
            'product_id' => (int) $product->id,
            'product_name' => $name,
            'category' => (string) ($product->category ?? ''),
            'sugar_grade' => (string) ($product->sugar_grade ?? '-'),
            'gr_sugar_content' => $sugarGram,
            'sugar_per_gram' => $netWeight > 0 ? round($sugarGram / $netWeight, 4) : 0.0,
            'net_weight' => $netWeight,
            'is_fallback_data' => $isFallbackData,
        ];
    }

    private function isFallbackBarcodeProductData($product): bool
    {
        $name = strtolower(trim((string) ($product->name ?? '')));
        return str_starts_with($name, 'produk barcode');
    }






    // Alur fungsi ini: app minta semua produk, backend ambil data produk lewat ProductService lalu kirim list produk.
    public function getAll()
    {
        try {
            $products = $this->productService->getAll();
            return successResponse($products, "All product retrieved successfully.");
        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'message' => $e->getMessage()
            ], 404);
        }
    }






    // Alur fungsi ini: app kirim query nama, backend cari produk yang cocok di database lalu kirim hasil pencarian.
    public function searchByName(Request $request)
    {
        $request->validate([
            'q' => 'required|string'
        ]);

        $products = $this->productService->searchByName($request->q);

        return successResponse($products, "Product list retrieved successfully.");
    }






    // Alur fungsi ini: app kirim label hasil scan/model, backend cocokkan ke produk database lalu kirim produk paling relevan.
    public function findByLabel(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'label' => 'required|string|max:255',
            'category' => 'nullable|in:food,drink',
        ]);

        $product = $this->productService->findBestByLabel(
            (string) $validated['label'],
            isset($validated['category']) ? (string) $validated['category'] : null
        );

        return successResponse($product, 'Produk berhasil dicocokkan dari label model.');
    }






    // Alur fungsi ini: request dari app diproses di controller (validasi + service/model/database), lalu response dikirim balik ke aplikasi.
    public function scanByBarcode(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'barcode' => 'required|string|max:64',
            'scan_source' => 'nullable|in:image_upload,camera_scan,manual_input',
        ]);

        $barcode = preg_replace('/\D+/', '', (string) ($validated['barcode'] ?? '')) ?? '';
        $scanSource = (string) ($validated['scan_source'] ?? 'unknown');
        $product = $this->productService->findProductByBarcode($barcode);

        if (!$product) {
            return errorResponse(
                'Barcode tidak terdaftar. Silakan cek ulang barcode atau pilih produk secara manual.',
                ['barcode' => $barcode],
                404
            );
        }

        $this->userBarcodeScanService->create([
            'user_id' => auth('sanctum')->id(),
            'product_id' => $product->id,
            'barcode' => $barcode,
            'scan_source' => $scanSource,
            'scanned_at' => now(),
        ]);

        return successResponse(
            $this->barcodeProductPayload($product, $barcode, $scanSource),
            'Barcode berhasil dipindai.'
        );
    }






    // Alur fungsi ini: request dari app diproses di controller (validasi + service/model/database), lalu response dikirim balik ke aplikasi.
    public function lookupBarcode(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'barcode' => 'required|string|max:64',
        ]);

        $barcode = preg_replace('/\D+/', '', (string) ($validated['barcode'] ?? '')) ?? '';
        $product = $this->productService->findProductByBarcode($barcode);

        if (!$product) {
            return errorResponse(
                'Barcode belum memiliki data produk dari sumber eksternal.',
                ['barcode' => $barcode],
                404
            );
        }

        return successResponse(
            $this->barcodeProductPayload($product, $barcode),
            'Barcode berhasil ditemukan.'
        );
    }






    // Alur fungsi ini: request dari app diproses di controller (validasi + service/model/database), lalu response dikirim balik ke aplikasi.
    public function registerByBarcode(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'barcode' => 'required|string|max:64',
            'scan_source' => 'nullable|in:image_upload,camera_scan,manual_input',
            'name' => 'required|string|max:255',
            'category' => 'required|in:food,drink',
            'gr_sugar_content' => 'required|numeric|min:0',
            'net_weight' => 'required|numeric|gt:0',
            'image' => 'nullable|string',
        ]);

        $barcode = preg_replace('/\D+/', '', (string) $validated['barcode']) ?? '';
        $scanSource = (string) ($validated['scan_source'] ?? 'unknown');
        if ($barcode === '') {
            return errorResponse('Barcode tidak valid.', ['barcode' => 'Barcode harus berisi angka.'], 422);
        }

        $payload = [
            'name' => (string) $validated['name'],
            'barcode' => $barcode,
            'category' => (string) $validated['category'],
            'image' => (string) ($validated['image'] ?? ''),
            'gr_sugar_content' => (float) $validated['gr_sugar_content'],
            'net_weight' => (float) $validated['net_weight'],
        ];

        $existing = $this->productService->findLocalProductRawByBarcode($barcode);
        if ($existing && !$this->isFallbackBarcodeProductData($existing)) {
            return errorResponse(
                'Barcode sudah terdaftar pada produk lain.',
                ['barcode' => $barcode, 'product_id' => $existing->id],
                422
            );
        }

        $product = $existing && $this->isFallbackBarcodeProductData($existing)
            ? $this->productService->update($existing, $payload)
            : $this->productService->create($payload);

        $result = $this->productService->findProductByBarcode($barcode);
        if (!$result) {
            return errorResponse('Produk barcode gagal dibuat.', null, 500);
        }

        $this->userBarcodeScanService->create([
            'user_id' => auth('sanctum')->id(),
            'product_id' => $product->id,
            'barcode' => $barcode,
            'scan_source' => $scanSource,
            'scanned_at' => now(),
        ]);

        return successResponse([
            'barcode' => $barcode,
            'scan_source' => $scanSource,
            'product_id' => (int) $result->id,
            'product_name' => (string) $result->name,
            'category' => (string) ($result->category ?? ''),
            'sugar_grade' => (string) ($result->sugar_grade ?? '-'),
            'gr_sugar_content' => (float) ($result->gr_sugar_content ?? 0),
            'sugar_per_gram' => $result->net_weight > 0 ? round(((float) $result->gr_sugar_content) / ((float) $result->net_weight), 4) : 0.0,
            'net_weight' => (float) ($result->net_weight ?? 0),
        ], 'Produk barcode berhasil didaftarkan.', 201);
    }






    // Alur fungsi ini: request dari app diproses di controller (validasi + service/model/database), lalu response dikirim balik ke aplikasi.
    public function recognizeNutritionLabel(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'name' => 'required|string|max:255',
            'category' => 'required|in:food,drink',
            'gr_sugar_content' => 'required|numeric|min:0',
            'net_weight' => 'required|numeric|gt:0',
            'image' => 'nullable|string',
            'product_image' => 'nullable|image|max:20480',
            'product_image_base64' => 'nullable|string',
            'scan_source' => 'nullable|in:image_upload,camera_scan,manual_input',
            'raw_text' => 'nullable|string',
        ]);

        $scanSource = (string) ($validated['scan_source'] ?? 'manual_input');
        $productImage = $this->normalizeNullableString($validated['image'] ?? '');
        if ($request->hasFile('product_image')) {
            $path = $request->file('product_image')->store('products', 'public');
            $productImage = url('storage/' . $path);
        } elseif (!empty($validated['product_image_base64'])) {
            $stored = $this->storeBase64ProductImage((string) $validated['product_image_base64']);
            if ($stored !== '') {
                $productImage = $stored;
            }
        }

        $result = $this->productService->findOrCreateFromNutritionLabel([
            'name' => (string) $validated['name'],
            'category' => (string) $validated['category'],
            'gr_sugar_content' => (float) $validated['gr_sugar_content'],
            'net_weight' => (float) $validated['net_weight'],
            'image' => $productImage,
            'raw_text' => (string) ($validated['raw_text'] ?? ''),
        ]);

        $product = $result['product'];
        $created = $result['created'] === true;

        return successResponse([
            'scan_source' => $scanSource,
            'matched_existing' => !$created,
            'product_id' => (int) $product->id,
            'product_name' => (string) $product->name,
            'category' => (string) ($product->category ?? ''),
            'sugar_grade' => (string) ($product->sugar_grade ?? '-'),
            'gr_sugar_content' => (float) ($product->gr_sugar_content ?? 0),
            'net_weight' => (float) ($product->net_weight ?? 0),
        ], $created ? 'Produk baru berhasil dibuat dari label gizi.' : 'Produk berhasil dicocokkan dari label gizi.', $created ? 201 : 200);
    }

    private function normalizeNullableString($value): string
    {
        $text = trim((string) $value);
        if ($text === '' || strtolower($text) === 'null' || strtolower($text) === 'undefined') {
            return '';
        }
        return $text;
    }

    private function storeBase64ProductImage(string $raw): string
    {
        $payload = trim($raw);
        if ($payload === '') {
            return '';
        }

        $extension = 'jpg';
        if (preg_match('/^data:image\/([a-zA-Z0-9+]+);base64,/', $payload, $matches) === 1) {
            $extension = strtolower($matches[1]);
            $payload = substr($payload, strpos($payload, ',') + 1);
        }

        if ($extension === 'jpeg') {
            $extension = 'jpg';
        }
        if (!in_array($extension, ['jpg', 'png', 'webp'], true)) {
            $extension = 'jpg';
        }

        $binary = base64_decode($payload, true);
        if ($binary === false) {
            return '';
        }

        $filename = 'products/' . uniqid('pack_', true) . '.' . $extension;
        $saved = Storage::disk('public')->put($filename, $binary);
        if (!$saved) {
            return '';
        }

        return url('storage/' . $filename);
    }






    // Alur fungsi ini: request dari app diproses di controller (validasi + service/model/database), lalu response dikirim balik ke aplikasi.
    public function detectNutritionLabelImage(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'image' => 'required|image|max:20480',
        ]);

        $detected = $this->nutritionVisionService->detectFromImage($validated['image']);

        return successResponse([
            'name' => (string) ($detected['name'] ?? ''),
            'category' => (string) ($detected['category'] ?? 'food'),
            'gr_sugar_content' => isset($detected['gr_sugar_content']) ? (float) $detected['gr_sugar_content'] : null,
            'net_weight' => isset($detected['net_weight']) ? (float) $detected['net_weight'] : null,
            'raw_text' => (string) ($detected['raw_text'] ?? ''),
            'label_text' => (string) ($detected['label_text'] ?? ''),
            'product_text' => (string) ($detected['product_text'] ?? ''),
        ], 'Gambar label gizi berhasil dianalisis.');
    }






    // Alur fungsi ini: request dari app diproses di controller (validasi + service/model/database), lalu response dikirim balik ke aplikasi.
    public function detectProductPackageImage(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'image' => 'required|image|max:20480',
        ]);

        $detected = $this->nutritionVisionService->detectFromImage($validated['image']);

        return successResponse([
            'name' => (string) ($detected['name'] ?? ''),
            'category' => (string) ($detected['category'] ?? 'food'),
            'raw_text' => (string) ($detected['raw_text'] ?? ''),
            'product_text' => '',
            'label_text' => (string) ($detected['label_text'] ?? ''),
            'gr_sugar_content' => isset($detected['gr_sugar_content']) ? (float) $detected['gr_sugar_content'] : null,
            'net_weight' => isset($detected['net_weight']) ? (float) $detected['net_weight'] : null,
        ], 'Gambar diproses dengan fokus label gizi.');
    }






    // Alur fungsi ini: request dari app diproses di controller (validasi + service/model/database), lalu response dikirim balik ke aplikasi.
    public function detectCompleteImage(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'package_image' => 'required|image|max:20480',
            'nutrition_image' => 'required|image|max:20480',
        ]);

        // Fokus label gizi: gunakan nutrition_image sebagai sumber utama.
        $nutritionDetected = $this->nutritionVisionService->detectFromImage($validated['nutrition_image']);

        return successResponse([
            'name' => (string) ($nutritionDetected['name'] ?? ''),
            'category' => (string) ($nutritionDetected['category'] ?? 'food'),
            'gr_sugar_content' => isset($nutritionDetected['gr_sugar_content']) ? (float) $nutritionDetected['gr_sugar_content'] : null,
            'net_weight' => isset($nutritionDetected['net_weight']) ? (float) $nutritionDetected['net_weight'] : null,
            'raw_text' => (string) ($nutritionDetected['raw_text'] ?? ''),
            'label_text' => (string) ($nutritionDetected['label_text'] ?? ''),
            'product_text' => '',
        ], 'Gambar diproses dengan fokus label gizi.');
    }






    // Alur fungsi ini: request dari app diproses di controller (validasi + service/model/database), lalu response dikirim balik ke aplikasi.
    public function detectBarcodeImage(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'image' => 'required|image|max:10240',
        ]);

        $detected = $this->nutritionVisionService->detectBarcodeFromImage($validated['image']);
        $barcode = preg_replace('/\D+/', '', (string) ($detected['barcode'] ?? '')) ?? '';
        if ($barcode === '') {
            return errorResponse('Barcode tidak berhasil dibaca dari gambar.', null, 422);
        }

        $product = $this->productService->findProductByBarcode($barcode);
        if (!$product) {
            return errorResponse(
                'Barcode berhasil dibaca, tetapi data produk belum tersedia dari sumber eksternal.',
                [
                    'barcode' => $barcode,
                    'raw_text' => (string) ($detected['raw_text'] ?? ''),
                ],
                404
            );
        }

        return successResponse(
            array_merge(
                $this->barcodeProductPayload($product, $barcode),
                [
                    'raw_text' => (string) ($detected['raw_text'] ?? ''),
                ]
            ),
            'Gambar barcode berhasil dianalisis.'
        );
    }






    // Alur fungsi ini: request dari app diproses di controller (validasi + service/model/database), lalu response dikirim balik ke aplikasi.
    public function getDetail($id)
    {
        try {
            $product = $this->productService->getDetailProduk((int) $id);
            return successResponse($product, "Detail produk retrieved successfully.");
        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'message' => $e->getMessage()
            ], 404);
        }
    }






    // Alur fungsi ini: request dari app diproses di controller (validasi + service/model/database), lalu response dikirim balik ke aplikasi.
    public function recommend($productId): JsonResponse
    {
        try {
            $product = $this->productService->findProductById($productId);
        } catch (\Throwable $e) {
            return successResponse([], "Product recommendations retrieved successfully.");
        }

        $currentSugarGrade = $product->sugar_grade;
        $currentCategory = $product->category;

        $similarProducts = $this->productService->getSameVarianProduct($currentCategory, $product->id);
        $gradeRank = ['Merah' => 3, 'Kuning' => 2, 'Hijau' => 1];

        if (!array_key_exists($currentSugarGrade, $gradeRank)) {
            return successResponse([], "Product recommendations retrieved successfully.");
        }

        // $recommendedProducts = $similarProducts->filter(function ($similarProduct) use ($gradeRank, $currentSugarGrade) {
        //     $similarGrade = sugarGrade(
        //         $similarProduct->category,
        //         $similarProduct->gr_sugar_content,
        //         $similarProduct->net_weight
        //     );

        //     $similarProduct->sugar_grade = $similarGrade;

        //     return $gradeRank[$similarGrade] < $gradeRank[$currentSugarGrade];
        // })->values();


        $recommendedProducts = $similarProducts->filter(function ($similarProduct) use ($gradeRank, $currentSugarGrade, $currentCategory) {
            if ($similarProduct->category !== $currentCategory) {
            return false;
        }
            $similarGrade = sugarGrade(
                $similarProduct->category,
                $similarProduct->gr_sugar_content,
                $similarProduct->net_weight
            );

            $similarProduct->sugar_grade = $similarGrade;

            if (!array_key_exists($similarGrade, $gradeRank)) {
                return false;
            }

            if ($currentSugarGrade === 'Hijau') {
                return $similarGrade === 'Hijau'; 
            }

            return $gradeRank[$similarGrade] < $gradeRank[$currentSugarGrade]; 
        })->values();


        return successResponse(RecProductResource::collection($recommendedProducts), "Product recommendations retrieved successfully.");
    }
}


