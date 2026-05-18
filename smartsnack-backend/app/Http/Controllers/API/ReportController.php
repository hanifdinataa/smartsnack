<?php

namespace App\Http\Controllers\API;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Services\UserConsumptionService;
use App\Services\SugarReportService;
use Illuminate\Http\JsonResponse;


class ReportController extends Controller
{
    protected $userConsumptionService;
    protected $sugarReportService;



    public function __construct(UserConsumptionService $userConsumptionService, SugarReportService $sugarReportService)
    {
        $this->userConsumptionService = $userConsumptionService;
        $this->sugarReportService = $sugarReportService;
    }






    // Alur fungsi ini: request dari app diproses di controller (validasi + service/model/database), lalu response dikirim balik ke aplikasi.
    public function todayRep()
    {
        $userId = auth('sanctum')->id();

        $totalSugarConsumed = $this->userConsumptionService->getTodayConsByUserId($userId);
        return successResponse($totalSugarConsumed, "Today's sugar consumption retrieved successfully.");
    }






    // Alur fungsi ini: request dari app diproses di controller (validasi + service/model/database), lalu response dikirim balik ke aplikasi.
    public function weeklyList()
    {
        $userId = auth('sanctum')->id();
        $data = $this->sugarReportService->getWeeklyReports($userId);

        return successResponse($data, "Available weekly reports retrieved successfully.");
    }






    // Alur fungsi ini: request dari app diproses di controller (validasi + service/model/database), lalu response dikirim balik ke aplikasi.
    public function monthlyList()
    {
        $userId = auth('sanctum')->id();
        $data = $this->sugarReportService->getMonthlyReports($userId);

        return successResponse($data, "Available monthly reports retrieved successfully.");
    }












    // Alur fungsi ini: request dari app diproses di controller (validasi + service/model/database), lalu response dikirim balik ke aplikasi.
    public function YearlyList()
    {
        $userId = auth('sanctum')->id();
        $data = $this->sugarReportService->getYearlyReports($userId);

        return successResponse($data, "Available yearly reports retrieved successfully.");
    }






    // Alur fungsi ini: request dari app diproses di controller (validasi + service/model/database), lalu response dikirim balik ke aplikasi.
    public function searchReports(): JsonResponse
    {
        $userId = auth('sanctum')->id();
        $query = request()->input('query', '');

        if (empty($query)) {
            return errorResponse("Query is required", 400);
        }

        $reports = $this->sugarReportService->searchReports($userId, $query);

        return successResponse($reports, "Reports search results retrieved successfully");
    }
}


