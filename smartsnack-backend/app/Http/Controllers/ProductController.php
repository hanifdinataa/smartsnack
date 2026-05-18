<?php

namespace App\Http\Controllers;

use App\Http\Controllers\Controller;
use App\Models\Product;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

class ProductController extends Controller
{
    // -------------------------------------------------------------------------
    // WEB CRUD
    // -------------------------------------------------------------------------
    // Alur fungsi ini: request masuk dari frontend, diproses di controller (validasi + service/model/database), lalu hasilnya dikirim balik sebagai response.
    public function index()
    {
        $products = Product::query()->orderBy('name')->get();
        return view('products.index', compact('products'));
    }

    // Alur fungsi ini: request masuk dari frontend, diproses di controller (validasi + service/model/database), lalu hasilnya dikirim balik sebagai response.

    public function create()
    {
        return view('products.create');
    }

    // Alur fungsi ini: request masuk dari frontend, diproses di controller (validasi + service/model/database), lalu hasilnya dikirim balik sebagai response.

    public function store(Request $request)
    {
        $validated = $request->validate([
            'name' => 'required|string|max:255',
            'category' => 'required|in:food,drink',
            'image' => 'nullable|string|max:2048',
            'gr_sugar_content' => 'required|numeric|min:0',
            'net_weight' => 'required|numeric|gt:0',
        ]);

        Product::create([
            'name' => (string) $validated['name'],
            'category' => (string) $validated['category'],
            'image' => (string) ($validated['image'] ?? ''),
            'gr_sugar_content' => (float) $validated['gr_sugar_content'],
            'net_weight' => (float) $validated['net_weight'],
        ]);

        return redirect()->route('products.index')->with('success', 'Produk berhasil dibuat.');
    }

    // Alur fungsi ini: request masuk dari frontend, diproses di controller (validasi + service/model/database), lalu hasilnya dikirim balik sebagai response.

    public function show(int $id)
    {
        $product = Product::findOrFail($id);
        return view('products.show', compact('product'));
    }

    // Alur fungsi ini: request masuk dari frontend, diproses di controller (validasi + service/model/database), lalu hasilnya dikirim balik sebagai response.

    public function edit(int $id)
    {
        $product = Product::findOrFail($id);
        return view('products.edit', compact('product'));
    }

    // Alur fungsi ini: request masuk dari frontend, diproses di controller (validasi + service/model/database), lalu hasilnya dikirim balik sebagai response.

    public function update(Request $request, int $id)
    {
        $product = Product::findOrFail($id);

        $validated = $request->validate([
            'name' => 'required|string|max:255',
            'category' => 'required|in:food,drink',
            'image' => 'nullable|string|max:2048',
            'gr_sugar_content' => 'required|numeric|min:0',
            'net_weight' => 'required|numeric|gt:0',
        ]);

        $product->update([
            'name' => (string) $validated['name'],
            'category' => (string) $validated['category'],
            'image' => (string) ($validated['image'] ?? ''),
            'gr_sugar_content' => (float) $validated['gr_sugar_content'],
            'net_weight' => (float) $validated['net_weight'],
        ]);

        return redirect()->route('products.index')->with('success', 'Produk berhasil diperbarui.');
    }

    // Alur fungsi ini: request masuk dari frontend, diproses di controller (validasi + service/model/database), lalu hasilnya dikirim balik sebagai response.

    public function destroy(int $id)
    {
        $product = Product::findOrFail($id);
        $product->delete();
        return redirect()->route('products.index')->with('success', 'Produk berhasil dihapus.');
    }

    // Alur fungsi ini: request masuk dari frontend, diproses di controller (validasi + service/model/database), lalu hasilnya dikirim balik sebagai response.

    public function destroyAll()
    {
        Product::query()->delete();
        return redirect()->route('products.index')->with('success', 'Semua produk berhasil dihapus.');
    }

    // -------------------------------------------------------------------------
    // GET /api/products
    // Ambil semua produk
    // -------------------------------------------------------------------------
    // Alur fungsi ini: request masuk dari frontend, diproses di controller (validasi + service/model/database), lalu hasilnya dikirim balik sebagai response.
    public function getAll()
    {
        $products = Product::orderBy('name')->get();

        return response()->json([
            'success' => true,
            'data'    => $products,
        ]);
    }

    // -------------------------------------------------------------------------
    // GET /api/products/search?q=Better
    //
    // FIX BUG 2:
    // Sebelumnya kemungkinan pakai WHERE name = ? (exact match) dan
    // return {success:false} kalau tidak ketemu.
    // Sekarang pakai LIKE fuzzy search dan SELALU return {success:true}
    // dengan array kosong kalau tidak ada hasil.
    // -------------------------------------------------------------------------
    // Alur fungsi ini: request masuk dari frontend, diproses di controller (validasi + service/model/database), lalu hasilnya dikirim balik sebagai response.
    public function searchByName(Request $request)
    {
        $query = trim($request->query('q', ''));

        if ($query === '') {
            // Kalau query kosong, kembalikan semua produk
            $products = Product::orderBy('name')->get();
            return response()->json([
                'success' => true,
                'data'    => $products,
            ]);
        }

        // Pecah query jadi token supaya "Better SANDWICH" bisa match
        // produk yang namanya "Better SANDWICH BISCUIT"
        $tokens = preg_split('/\s+/', $query, -1, PREG_SPLIT_NO_EMPTY);

        $dbQuery = Product::query();

        foreach ($tokens as $token) {
            // Tiap token harus ada di name (AND per token, case-insensitive)
            $dbQuery->where('name', 'LIKE', '%' . $token . '%');
        }

        $products = $dbQuery->orderBy('name')->get();

        // FIX: Selalu return success:true, walau array kosong.
        // Kalau return success:false, _extractMap() di Flutter akan throw Exception
        // dan membuat findProductByLabel() crash sebelum sampai ke fallback.
        return response()->json([
            'success' => true,
            'data'    => $products,
        ]);
    }

    // -------------------------------------------------------------------------
    // GET /api/products/find-by-label?label=Better
    //
    // FIX: Gunakan LIKE search supaya label model TFLite yang tidak persis
    // sama dengan nama di database tetap bisa ditemukan.
    // Contoh: label "Better" ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ cocok dengan "Better SANDWICH BISCUIT"
    // -------------------------------------------------------------------------
    // Alur fungsi ini: request masuk dari frontend, diproses di controller (validasi + service/model/database), lalu hasilnya dikirim balik sebagai response.
    public function findByLabel(Request $request)
    {
        $label = trim($request->query('label', ''));

        if ($label === '') {
            return response()->json([
                'success' => true,
                'data'    => null,
            ]);
        }

        // Coba exact match dulu (paling akurat)
        $product = Product::whereRaw('LOWER(name) = ?', [strtolower($label)])->first();

        // Kalau tidak ketemu, coba LIKE (label bisa berupa sebagian nama)
        if (!$product) {
            $product = Product::where('name', 'LIKE', '%' . $label . '%')
                ->orderByRaw('LENGTH(name) ASC') // Pilih nama terpendek = paling relevan
                ->first();
        }

        // Kalau masih tidak ketemu, coba tiap kata dari label
        if (!$product) {
            $tokens = preg_split('/\s+/', $label, -1, PREG_SPLIT_NO_EMPTY);
            $query  = Product::query();
            foreach ($tokens as $token) {
                if (strlen($token) >= 3) {
                    $query->orWhere('name', 'LIKE', '%' . $token . '%');
                }
            }
            $product = $query->orderByRaw('LENGTH(name) ASC')->first();
        }

        return response()->json([
            'success' => true,
            'data'    => $product, // null kalau benar-benar tidak ada
        ]);
    }

    // -------------------------------------------------------------------------
    // GET /api/products/{id}
    // -------------------------------------------------------------------------
    // Alur fungsi ini: request masuk dari frontend, diproses di controller (validasi + service/model/database), lalu hasilnya dikirim balik sebagai response.
    public function getDetail($id)
    {
        $product = Product::find($id);

        if (!$product) {
            return response()->json([
                'success' => false,
                'message' => 'Produk tidak ditemukan.',
            ], 404);
        }

        return response()->json([
            'success' => true,
            'data'    => $product,
        ]);
    }

    // -------------------------------------------------------------------------
    // POST /api/products/recognize-nutrition-label
    // Simpan produk baru dari hasil scan label gizi
    // -------------------------------------------------------------------------
    // Alur fungsi ini: request masuk dari frontend, diproses di controller (validasi + service/model/database), lalu hasilnya dikirim balik sebagai response.
    public function recognizeNutritionLabel(Request $request)
    {
        $request->validate([
            'name'            => 'required|string|max:255',
            'category'        => 'required|in:food,drink',
            'gr_sugar_content'=> 'required|numeric|min:0',
            'net_weight'      => 'required|numeric|min:0.1',
        ]);

        $imagePath = null;

        // Handle upload gambar (multipart atau base64)
        if ($request->hasFile('product_image')) {
            $file      = $request->file('product_image');
            $filename  = 'pack_' . uniqid() . '.' . $file->getClientOriginalExtension();
            $imagePath = $file->storeAs('products', $filename, 'public');
        } elseif ($request->filled('product_image_base64')) {
            $base64 = $request->input('product_image_base64');
            if (preg_match('/^data:image\/(\w+);base64,/', $base64, $type)) {
                $base64   = substr($base64, strpos($base64, ',') + 1);
                $ext      = strtolower($type[1]);
                $filename = 'pack_' . uniqid() . '.' . $ext;
                Storage::disk('public')->put('products/' . $filename, base64_decode($base64));
                $imagePath = 'products/' . $filename;
            }
        }

        $product = Product::create([
            'name'             => trim($request->input('name')),
            'category'         => $request->input('category'),
            'gr_sugar_content' => $request->input('gr_sugar_content'),
            'net_weight'       => $request->input('net_weight'),
            'image'            => $imagePath
                                    ? Storage::disk('public')->url($imagePath)
                                    : null,
        ]);

        return response()->json([
            'success' => true,
            'data'    => [
                'product_name'    => $product->name,
                'category'        => $product->category,
                'gr_sugar_content'=> (float) $product->gr_sugar_content,
                'net_weight'      => (float) $product->net_weight,
                'image'           => $product->image,
            ],
        ]);
    }

    // -------------------------------------------------------------------------
    // GET /api/recommendation/{product_id}
    // Rekomendasi produk dengan gula lebih rendah dari kategori yang sama
    // -------------------------------------------------------------------------
    // Alur fungsi ini: request masuk dari frontend, diproses di controller (validasi + service/model/database), lalu hasilnya dikirim balik sebagai response.
    public function recommend($product_id)
    {
        $product = Product::find($product_id);

        if (!$product) {
            return response()->json([
                'success' => true,
                'data'    => [],
            ]);
        }

        $recommendations = Product::where('category', $product->category)
            ->where('id', '!=', $product->id)
            ->where('gr_sugar_content', '<=', $product->gr_sugar_content)
            ->orderBy('gr_sugar_content')
            ->limit(5)
            ->get();

        return response()->json([
            'success' => true,
            'data'    => $recommendations,
        ]);
    }

    // -------------------------------------------------------------------------
    // POST /api/products/detect-nutrition-image
    // Deteksi label gizi dari gambar (OCR via backend)
    // -------------------------------------------------------------------------
    // Alur fungsi ini: request masuk dari frontend, diproses di controller (validasi + service/model/database), lalu hasilnya dikirim balik sebagai response.
    public function detectNutritionLabelImage(Request $request)
    {
        $request->validate([
            'image' => 'required|image|max:10240',
        ]);

        // Implementasi OCR (sesuaikan dengan library yang kamu pakai,
        // misalnya Tesseract atau Google Vision API)
        // Ini contoh response structure yang diharapkan Flutter:
        return response()->json([
            'success' => true,
            'data'    => [
                'gr_sugar_content' => null,
                'net_weight'       => null,
                'raw_text'         => '',
            ],
        ]);
    }

    // -------------------------------------------------------------------------
    // POST /api/products/detect-package-image
    // -------------------------------------------------------------------------
    // Alur fungsi ini: request masuk dari frontend, diproses di controller (validasi + service/model/database), lalu hasilnya dikirim balik sebagai response.
    public function detectProductPackageImage(Request $request)
    {
        $request->validate([
            'image' => 'required|image|max:10240',
        ]);

        return response()->json([
            'success' => true,
            'data'    => [
                'gr_sugar_content' => null,
                'net_weight'       => null,
                'raw_text'         => '',
            ],
        ]);
    }

    // -------------------------------------------------------------------------
    // POST /api/products/detect-complete-image
    // -------------------------------------------------------------------------
    // Alur fungsi ini: request masuk dari frontend, diproses di controller (validasi + service/model/database), lalu hasilnya dikirim balik sebagai response.
    public function detectCompleteImage(Request $request)
    {
        return response()->json([
            'success' => true,
            'data'    => [
                'gr_sugar_content' => null,
                'net_weight'       => null,
                'raw_text'         => '',
            ],
        ]);
    }
}

