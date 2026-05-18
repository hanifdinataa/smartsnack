<?php

namespace App\Repositories;

use App\Models\SugarReport;

class SugarReportRepository
{
    public function findReport(int $userId, int $weekNumber, string $month, int $year)
    {
        return SugarReport::where('user_id', $userId)
            ->where('week_number', $weekNumber)
            ->where('month', $month)
            ->where('year', $year)
            ->first();
    }

    public function createReport(int $userId, int $weekNumber, string $month, int $year)
    {
        return SugarReport::create([
            'user_id' => $userId,
            'week_number' => $weekNumber,
            'month' => $month,
            'year' => $year,
            'report' => "Minggu {$weekNumber}\n{$month} {$year}"
        ]);
    }

    public function getWeeklyReports(int $userId)
    {
        return SugarReport::where('user_id', $userId)
            ->orderBy('year', 'desc')
            ->orderBy('month', 'desc')
            ->orderBy('week_number', 'desc')
            ->get();
    }

    public function getMonthlyReports(int $userId)
    {
        return SugarReport::select('month', 'year')
            ->where('user_id', $userId)
            ->distinct()
            ->orderBy('year', 'desc')
            ->orderBy('month', 'desc')
            ->get();
    }

    public function getYearlyReports(int $userId)
    {
        return SugarReport::select('year')
            ->where('user_id', $userId)
            ->distinct()
            ->orderBy('year', 'desc')
            ->get();
    }

    public function searchReports(int $userId, string $query)
    {
        return SugarReport::where('user_id', $userId)
            ->where(function ($q) use ($query) {
                $q->where('report', 'LIKE', "%{$query}%")
                    ->orWhere('week_number', 'LIKE', "%{$query}%")
                    ->orWhere('month', 'LIKE', "%{$query}%")
                    ->orWhere('year', 'LIKE', "%{$query}%");
            })
            ->orderBy('year', 'desc')
            ->orderBy('month', 'desc')
            ->orderBy('week_number', 'desc')
            ->get();
    }
}
