<?php

namespace App\Http\Controllers\API;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Services\UserConsumptionService;
use App\Services\ProductService;
use App\Services\SnackBoxAccessService;
use App\Http\Requests\StoreUserConsumptionRequest;
use Illuminate\Http\JsonResponse;
use App\Http\Resources\UserConsumptionResource;
use Throwable;


class UserConsumptionController extends Controller
{
    protected $userconsService;
    protected $productService;
    protected $snackBoxAccessService;



    public function __construct(
        UserConsumptionService $userconsService,
        ProductService $productService,
        SnackBoxAccessService $snackBoxAccessService
    )
    {
        $this->userconsService = $userconsService;
        $this->productService = $productService;
        $this->snackBoxAccessService = $snackBoxAccessService;
    }






    // Alur fungsi ini: request dari app diproses di controller (validasi + service/model/database), lalu response dikirim balik ke aplikasi.
    public function index(): JsonResponse
    {
        $userId = auth('sanctum')->id();
        $data = $this->userconsService->getByUserId($userId)->load('product');

        $data = $data->map(function ($item) {
            $amount = $this->amountConsumed($item->product_id, $item->percentage_consumed);

            $category = $item->product->category ?? null;

            if ($category === 'drink') {
                $item->amountConsumed = $amount . ' ml';
            } elseif ($category === 'food') {
                $item->amountConsumed = $amount . ' gr';
            } else {
                $item->amountConsumed = $amount;
            }

            return $item;
        });

        return successResponse(
            UserConsumptionResource::collection($data),
            "User consumption successfully retrieved"
        );
    }






    // Alur fungsi ini: request dari app diproses di controller (validasi + service/model/database), lalu response dikirim balik ke aplikasi.
    public function store(StoreUserConsumptionRequest $request): JsonResponse
    {
        try {
            $data = $request->validated();
            $data['user_id'] = auth('sanctum')->id();
            $data['product_id'] = $request->product_id;
            $data['date'] = getCurrentDate();

            $category = $this->productService->findProductCategoryById($request->product_id);
            $sugarConsumed = $this->sugarConsumed($request->product_id, $request->percentage_consumed);
            $amountConsumed = $this->amountConsumed($request->product_id, $request->percentage_consumed);

            $this->snackBoxAccessService->ensureCanConsume((int) $data['user_id'], $sugarConsumed);

            $data['sugar_grade'] = sugarGrade($category, $sugarConsumed, $amountConsumed);
            $data['percentage_consumed'] = $request->percentage_consumed;
            $data['gr_sugar_consumed'] = $sugarConsumed;

            $this->userconsService->create($data);
            $status = $this->snackBoxAccessService->getStatusForUser((int) $data['user_id']);

            return successResponse(
                $data + ['snack_box_status' => $status],
                "User consumption record created successfully"
            );
        } catch (Throwable $e) {
            return errorResponse($e->getMessage(), null, 422);
        }
    }






    // Alur fungsi ini: request dari app diproses di controller (validasi + service/model/database), lalu response dikirim balik ke aplikasi.
    public function destroy(int $id): JsonResponse
    {
        $userId = auth('sanctum')->id();
        $deleted = $this->userconsService->deleteByUserAndId($userId, $id);
        if (!$deleted) {
            return errorResponse('Data konsumsi tidak ditemukan.', null, 404);
        }

        $status = $this->snackBoxAccessService->getStatusForUser((int) $userId);

        return successResponse([
            'id' => $id,
            'snack_box_status' => $status,
        ], 'Data konsumsi berhasil dihapus.');
    }






    // Alur fungsi ini: request dari app diproses di controller (validasi + service/model/database), lalu response dikirim balik ke aplikasi.
    public function destroyAll(): JsonResponse
    {
        $userId = auth('sanctum')->id();
        $deletedCount = $this->userconsService->deleteAllByUserId((int) $userId);
        $status = $this->snackBoxAccessService->getStatusForUser((int) $userId);

        return successResponse([
            'deleted_count' => $deletedCount,
            'snack_box_status' => $status,
        ], 'Semua data konsumsi berhasil dihapus.');
    }






    // Alur fungsi ini: request dari app diproses di controller (validasi + service/model/database), lalu response dikirim balik ke aplikasi.
    public function sugarConsumed(int $productId, float $percentageConsumed): float
    {
        $sugar = (float) ($this->productService->findSugarProductById($productId) ?? 0);
        return $percentageConsumed * $sugar;
    }






    // Alur fungsi ini: request dari app diproses di controller (validasi + service/model/database), lalu response dikirim balik ke aplikasi.
    public function amountConsumed(int $productId, float $percentageConsumed): float
    {
        $netWeight = (float) ($this->productService->findNetWeightById($productId) ?? 0);

        return $percentageConsumed * $netWeight;
    }






    // Alur fungsi ini: request dari app diproses di controller (validasi + service/model/database), lalu response dikirim balik ke aplikasi.
    public function getConsumptionByReport(int $sugarReportId): JsonResponse
    {
        $userId = auth('sanctum')->id();
        $data = $this->userconsService->getUserConsByRepId($userId, $sugarReportId);

        return successResponse($data, "Consumption data retrieved successfully");
    }












    // Alur fungsi ini: request dari app diproses di controller (validasi + service/model/database), lalu response dikirim balik ke aplikasi.
    public function getMonthlyConsumptionByReport(): JsonResponse
    {
        $userId = auth('sanctum')->id();
        $month = request()->input('month');
        $year = request()->input('year');
        if (!$month || !$year) {
            return errorResponse("Month and year are required", 400);
        }

        $consumptions = $this->userconsService->getMonthlyConsumption($userId, $month, $year);

        return successResponse($consumptions, "Consumption data retrieved successfully");
    }






    // Alur fungsi ini: request dari app diproses di controller (validasi + service/model/database), lalu response dikirim balik ke aplikasi.
    public function getYearlyConsumptionReport(): JsonResponse
    {
        $userId = auth('sanctum')->id();
        $year = request()->input('year');

        if (!$year) {
            return errorResponse("Year is required", 400);
        }

        $consumptions = $this->userconsService->getYearlyConsumption($userId, $year);

        return successResponse($consumptions, "Yearly consumption summary retrieved successfully");
    }
}


