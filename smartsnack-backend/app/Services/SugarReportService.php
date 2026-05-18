<?php

namespace App\Services;

use App\Models\User;
use App\Repositories\SugarReportRepository;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Hash;
use Carbon\Carbon;
use App\Models\UserConsumption;

class SugarReportService
{
    protected SugarReportRepository $sugarReportRepository;

    public function __construct(SugarReportRepository $sugarReportRepository)
    {
        $this->sugarReportRepository = $sugarReportRepository;
    }

    public function getWeeklyReports(int $userId)
    {
        return $this->sugarReportRepository->getWeeklyReports($userId);
    }

    public function getMonthlyReports(int $userId)
    {
        return $this->sugarReportRepository->getMonthlyReports($userId);
    }

    public function getYearlyReports(int $userId)
    {
        return $this->sugarReportRepository->getYearlyReports($userId);
    }

    public function searchReports(int $userId, string $query)
    {
        return $this->sugarReportRepository->searchReports($userId, $query);
    }
}
