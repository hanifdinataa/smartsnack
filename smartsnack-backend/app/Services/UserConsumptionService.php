<?php

namespace App\Services;

use App\Repositories\UserConsumptionRepository;
use App\Repositories\SugarReportRepository;
use Carbon\Carbon;

Carbon::setLocale('id');

class UserConsumptionService
{
    protected $repository;
    protected $sugarReportRepository;

    public function __construct(UserConsumptionRepository $repository, SugarReportRepository $sugarReportRepository)
    {
        $this->repository = $repository;
        $this->sugarReportRepository = $sugarReportRepository;
    }

    public function getByUserId(int $userId)
    {
        $products = $this->repository->getByUserId($userId);
        foreach ($products as $product) {

            $product->percentage_consumed = (float) $product->percentage_consumed;
            $product->gr_sugar_consumed = (float) $product->gr_sugar_consumed;

            $product->makeHidden([
                'id',
                'user_id',
                'created_at',
                'updated_at'
            ]);
        }

        return $products;
    }

    // public function create(array $data)
    // {
    //     return $this->repository->create($data);
    // }

    public function create(array $data)
    {
        $consumptionDate = Carbon::parse($data['date']);
        $weekInfo = $this->determineWeekNumber($consumptionDate);

        // Cek laporan mingguan 
        $sugarReport = $this->sugarReportRepository->findReport(
            $data['user_id'],
            $weekInfo['week_number'],
            $weekInfo['month'],
            $weekInfo['year']
        );

        if (!$sugarReport) {
            $sugarReport = $this->sugarReportRepository->createReport(
                $data['user_id'],
                $weekInfo['week_number'],
                $weekInfo['month'],
                $weekInfo['year']
            );
        }

        // Simpan konsumsi dan kaitkan dengan laporan mingguan yang benar
        $data['sugar_report_id'] = $sugarReport->id;
        return $this->repository->create($data);
    }

    public function getTodayConsByUserId(int $userId)
    {
        $total = $this->repository->getTodayConsByUserId($userId);
        return (float)$total ?? 0;
    }

    public function deleteByUserAndId(int $userId, int $id): bool
    {
        $item = $this->repository->findByUserAndId($userId, $id);
        if (!$item) {
            return false;
        }
        return $this->repository->delete($item);
    }

    public function deleteAllByUserId(int $userId): int
    {
        return $this->repository->deleteAllByUserId($userId);
    }




    public function determineWeekNumber(Carbon $date): array
    {
        $firstDayOfMonth = $date->copy()->startOfMonth();
        $firstSunday = $firstDayOfMonth->copy()->next(Carbon::SUNDAY);

        // Minggu pertama: tanggal 1 hingga hari Minggu pertama bulan itu
        if ($date->lessThanOrEqualTo($firstSunday)) {
            $weekNumber = 1;
            $weekStart = $firstDayOfMonth;
            $weekEnd = $firstSunday;
        } else {
            // Minggu berikutnya: mulai dari Senin setelah Minggu pertama
            $weekNumber = 2;
            $weekStart = $firstSunday->copy()->addDay();
            $weekEnd = $weekStart->copy()->endOfWeek(Carbon::SUNDAY);

            while ($weekEnd->lessThan($date)) {
                $weekStart = $weekEnd->copy()->addDay();
                $weekEnd = $weekStart->copy()->endOfWeek(Carbon::SUNDAY);
                $weekNumber++;
            }
        }

        return [
            'week_number' => $weekNumber,
            'month' => Carbon::parse($date)->translatedFormat('F'),
            'year' => $date->year,
        ];
    }

    public function getUserConsByRepId(int $userId, int $repId)
    {
        $data = $this->repository->getUserConsByRepId($userId, $repId);
        return $data->map(function ($item) {
            $item->total_sugar = (float) $item->total_sugar;
            return $item;
        });
    }

    public function getMonthlyConsumption(int $userId, string $month, int $year)
    {
        $data = $this->repository->getMonthlyConsumption($userId,  $month,  $year);

        return $data->map(function ($item) {
            $item->total_sugar = (float) $item->total_sugar;
            return $item;
        });
    }

    public function getYearlyConsumption(int $userId, int $year)
    {
        $data = $this->repository->getYearlyConsumption($userId, $year);

        return $data->map(function ($item) {
            $item->total_sugar = (float) $item->total_sugar;
            return $item;
        });
    }
}
