<?php

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;
use App\Models\User;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;
use App\Http\Controllers\API\AuthController;
use App\Http\Controllers\API\UserController;
use App\Http\Controllers\API\ProductController;
use App\Http\Controllers\API\ReportController;
use App\Http\Controllers\API\ImageClassificationController;
use App\Http\Controllers\API\UserConsumptionController;
use App\Http\Controllers\API\UserSearchHistoryController;
use App\Http\Controllers\API\SuggestedProductController;
use App\Http\Controllers\API\ArticleController;
use App\Http\Controllers\API\HealthMonitoringController;
use App\Http\Controllers\API\SnackBoxController;

// =========================================================
// API ROUTES SMARTSNACK
// Catatan:
// - File ini adalah "pintu masuk" semua request dari Flutter/web ke backend.
// - Format umum: Route::<method>('<url>', [Controller::class, 'method']);
// - Endpoint di bawah group auth:sanctum wajib pakai token login.
// =========================================================

// AUTH PUBLIC (belum perlu login)
// Register akun baru user.
Route::post('/register', [AuthController::class, 'register']);
// Login user, biasanya backend mengembalikan token untuk akses endpoint private.
Route::post('/login', [AuthController::class, 'login']);


Route::middleware('auth:sanctum')->group(function () {
    // =====================================================
    // AUTH PRIVATE + PROFILE (wajib login/token)
    // =====================================================
    // Ambil data profil user yang sedang login.
    Route::get('/user', [UserController::class, 'profile']);
    // Update data profil user (nama/email, dst).
    Route::patch('/user', [UserController::class, 'update']);
    // Logout user (token/sesi tidak dipakai lagi).
    Route::post('/logout', [AuthController::class, 'logout']);


    // =====================================================
    // PRODUK + SCAN/OCR + KLASIFIKASI
    // =====================================================
    // Klasifikasi gambar produk (alur model image classifier).
    Route::post('/classify-product', [ImageClassificationController::class, 'classify']);
    // Ambil semua produk dari database.
    Route::get('/products', [ProductController::class, 'getAll']);
    // Upload foto label gizi, lalu backend panggil OCR/vision service.
    Route::post('/products/detect-nutrition-image', [ProductController::class, 'detectNutritionLabelImage']);
    // Upload foto kemasan, dipakai untuk deteksi info produk dari gambar kemasan.
    Route::post('/products/detect-package-image', [ProductController::class, 'detectProductPackageImage']);
    // Upload paket lengkap (misalnya kemasan + label) untuk deteksi gabungan.
    Route::post('/products/detect-complete-image', [ProductController::class, 'detectCompleteImage']);
    // Simpan/olah hasil pembacaan label gizi menjadi data produk yang bisa dipakai app.
    Route::post('/products/recognize-nutrition-label', [ProductController::class, 'recognizeNutritionLabel']);
    // Cari produk berdasarkan nama/keyword dari input user.
    Route::get('/products/search', [ProductController::class, 'searchByName']);
    // Cari produk berdasarkan label hasil scan/model (label -> produk DB).
    Route::get('/products/find-by-label', [ProductController::class, 'findByLabel']);
    // Ambil detail satu produk berdasarkan ID.
    Route::get('/products/{id}', [ProductController::class, 'getDetail']);

    // REKOMENDASI PRODUK
    // Ambil rekomendasi produk berdasarkan product_id yang dipilih user.
    Route::get('/recommendation/{product_id}', [ProductController::class, 'recommend']);

    // =====================================================
    // KONSUMSI USER (riwayat apa yang dikonsumsi user)
    // =====================================================
    Route::prefix('user-consumption')->group(function () {
        // Simpan data konsumsi baru user.
        Route::post('/', [UserConsumptionController::class, 'store']);
        // Ambil daftar konsumsi user.
        Route::get('/', [UserConsumptionController::class, 'index']);
        // Hapus semua riwayat konsumsi user.
        Route::delete('/', [UserConsumptionController::class, 'destroyAll']);
        // Hapus satu data konsumsi berdasarkan ID.
        Route::delete('/{id}', [UserConsumptionController::class, 'destroy']);
    });

    // =====================================================
    // MONITORING KESEHATAN (sensor + analisis risiko)
    // =====================================================
    Route::prefix('health-monitoring')->group(function () {
        // Trigger cek detak jantung (umumnya ambil data dari perangkat via MQTT).
        Route::post('/check-heart-rate', [HealthMonitoringController::class, 'checkHeartRate']);
        // Trigger cek suhu tubuh dari perangkat.
        Route::post('/check-body-temperature', [HealthMonitoringController::class, 'checkBodyTemperature']);
        // Proses analisis risiko diabetes (backend akan pakai service/model XGBoost).
        Route::post('/analyze', [HealthMonitoringController::class, 'analyze']);
        // Ambil riwayat hasil monitoring kesehatan user.
        Route::get('/history', [HealthMonitoringController::class, 'history']);
    });

    // =====================================================
    // SMART SNACK BOX (IoT)
    // =====================================================
    Route::prefix('snack-box')->group(function () {
        // Aktivasi proses akses snack box (alur izin buka).
        Route::post('/activate', [SnackBoxController::class, 'activate']);
        // Cek status snack box/perangkat.
        Route::get('/status', [SnackBoxController::class, 'status']);
    });

    // =====================================================
    // RIWAYAT PENCARIAN PRODUK USER
    // =====================================================
    Route::prefix('user-search-history-product')->group(function () {
        // Simpan keyword/produk yang dicari user.
        Route::post('/', [UserSearchHistoryController::class, 'store']);
        // Ambil riwayat pencarian user.
        Route::get('/', [UserSearchHistoryController::class, 'index']);
    });

    // =====================================================
    // REPORT/LAPORAN KONSUMSI GULA
    // =====================================================
    Route::prefix('report')->group(function () {
        // Ringkasan konsumsi gula hari ini.
        Route::get('/user/sugar/today', [ReportController::class, 'todayRep']);

        // Daftar laporan per periode.
        // List mingguan.
        Route::get('/user/sugar/weekly-list', [ReportController::class, 'weeklyList']);
        // List bulanan.
        Route::get('/user/sugar/monthly-list', [ReportController::class, 'monthlyList']);
        // List tahunan.
        Route::get('/user/sugar/yearly-list', [ReportController::class, 'yearlyList']);

        // Search laporan berdasarkan filter tertentu.
        Route::get('/user/sugar/search', [ReportController::class, 'searchReports']);

        // Data untuk grafik/chart konsumsi.
        // Detail konsumsi berdasarkan report ID.
        Route::get('/user/consumption/{sugarReportId}', [UserConsumptionController::class, 'getConsumptionByReport']);
        // Data agregasi bulanan untuk chart.
        Route::get('/user/monthly-consumption', [UserConsumptionController::class, 'getMonthlyConsumptionByReport']);
        // Data agregasi tahunan untuk chart.
        Route::get('/user/yearly-consumption', [UserConsumptionController::class, 'getYearlyConsumptionReport']);
    });

    // =====================================================
    // SARAN PRODUK BARU
    // =====================================================
    // User bisa mengusulkan produk baru jika belum ada di database.
    Route::post('/suggested-products', [SuggestedProductController::class, 'store']);

    // =====================================================
    // ARTIKEL (CRUD)
    // =====================================================
    // Ambil daftar artikel.
    Route::get('/articles', [ArticleController::class, 'index']);
    // Ambil detail satu artikel.
    Route::get('/articles/{id}', [ArticleController::class, 'show']);
    // Buat artikel baru.
    Route::post('/articles', [ArticleController::class, 'store']);
    // Update artikel.
    Route::patch('/articles/{id}', [ArticleController::class, 'update']);
    // Hapus artikel.
    Route::delete('/articles/{id}', [ArticleController::class, 'destroy']);
});
