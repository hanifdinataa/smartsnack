<?php

namespace App\Repositories;

use App\Models\UserConsumption;
use Illuminate\Support\Facades\DB;


class UserConsumptionRepository
{
    protected $model;

    public function __construct(UserConsumption $model)
    {
        $this->model = $model;
    }

    public function getByUserId(int $userId)
    {
        return $this->model
            ->where('user_id', $userId)
            ->orderBy('created_at', 'desc')
            ->get();
    }

    public function create(array $data)
    {
        return $this->model->create($data);
    }

    public function findByUserAndId(int $userId, int $id): ?UserConsumption
    {
        return $this->model->where('user_id', $userId)->where('id', $id)->first();
    }

    public function delete(UserConsumption $item): bool
    {
        return (bool) $item->delete();
    }

    public function deleteAllByUserId(int $userId): int
    {
        return (int) $this->model->where('user_id', $userId)->delete();
    }

    public function getTodayConsByUserId(int $userId)
    {
        $today = getCurrentDate();
        return $this->model
            ->where('user_id', $userId)
            ->where('date', $today)
            ->sum('gr_sugar_consumed');
    }

    public function getUserConsByRepId(int $userId, int $repId)
    {
        return $this->model
            ->select([
                'user_id',
                DB::raw('DAY(date) as day'),
                DB::raw('SUM(gr_sugar_consumed) as total_sugar'),
                DB::raw('MONTHNAME(date) as month'),
                DB::raw('CASE 
                            WHEN SUM(gr_sugar_consumed) > 25 THEN "Merah" 
                            ELSE "Hijau" 
                          END as sugar_grade')
            ])
            ->where('user_id', $userId)
            ->where('sugar_report_id', $repId)
            ->groupBy('user_id', 'date')->orderBy('date', 'asc')
            ->get();
    }


    public function getMonthlyConsumption(int $userId, string $month, int $year)
    {
        return UserConsumption::select(
            'sugar_reports.week_number',
            DB::raw('SUM(user_consumptions.gr_sugar_consumed) as total_sugar'),
            DB::raw('COUNT(DISTINCT DATE(user_consumptions.date)) as total_days'), // Hitung jumlah hari unik dengan konsumsi
            DB::raw('CASE 
                        WHEN SUM(user_consumptions.gr_sugar_consumed) <= (COUNT(DISTINCT DATE(user_consumptions.date)) * 25) THEN "Hijau" 
                        ELSE "Merah" 
                     END as sugar_grade') // Hitung grade berdasarkan batas konsumsi
        )
            ->join('sugar_reports', 'user_consumptions.sugar_report_id', '=', 'sugar_reports.id') // Hubungkan dengan `sugar_report`
            ->where('sugar_reports.month', $month) // Filter berdasarkan bulan yang diklik user
            ->where('sugar_reports.year', $year) // Pastikan tahun juga sesuai
            ->where('user_consumptions.user_id', $userId)
            ->groupBy('sugar_reports.week_number')
            ->orderBy('sugar_reports.week_number', 'asc')
            ->get();
    }

    public function getYearlyConsumption(int $userId, int $year)
    {
        return UserConsumption::select(
            DB::raw('MONTHNAME(date) as month'),
            DB::raw('SUM(gr_sugar_consumed) as total_sugar'),
            DB::raw('COUNT(DISTINCT DATE(date)) as total_days'), // Hitung jumlah hari unik dengan konsumsi
            DB::raw('CASE 
                            WHEN SUM(gr_sugar_consumed) <= (COUNT(DISTINCT DATE(date)) * 25) THEN "Hijau" 
                            ELSE "Merah" 
                         END as sugar_grade') // Hitung grade berdasarkan batas konsumsi
        )
            ->whereYear('date', $year) // Filter berdasarkan tahun yang diklik user
            ->where('user_id', $userId)
            ->groupBy(DB::raw('MONTHNAME(date)'))
            ->orderBy(DB::raw('MONTH(date)'), 'asc')
            ->get();
    }



    // public function getWeeklyReportPresence(int $userId)
    // {
    //     $data = $this->model
    //         ->select('date')
    //         ->where('user_id', $userId)
    //         ->orderBy('date', 'asc')
    //         ->get();

    //     $results = [];

    //     foreach ($data as $item) {
    //         $date = Carbon::parse($item->date);
    //         $firstDayOfMonth = $date->copy()->startOfMonth();
    //         $firstSunday = $firstDayOfMonth->copy()->next(Carbon::SUNDAY);

    //         // Minggu pertama: mulai dari tanggal 1 hingga hari Minggu pertama bulan tersebut
    //         if ($date->lessThanOrEqualTo($firstSunday)) {
    //             $weekNumber = 1;
    //             $weekStart = $firstDayOfMonth;
    //             $weekEnd = $firstSunday;
    //         } else {
    //             // Minggu-minggu berikutnya: mulai dari hari Senin dan berakhir di hari Minggu
    //             $weekNumber = 2;
    //             $weekStart = $firstSunday->copy()->addDay(); // Mulai dari Senin setelah minggu pertama
    //             $weekEnd = $weekStart->copy()->endOfWeek(Carbon::SUNDAY);

    //             while ($weekEnd->lessThan($date)) {
    //                 $weekStart = $weekEnd->copy()->addDay();
    //                 $weekEnd = $weekStart->copy()->endOfWeek(Carbon::SUNDAY);
    //                 $weekNumber++;
    //             }
    //         }

    //         // Simpan hasil berdasarkan minggu
    //         $weekKey = "{$weekNumber}-{$date->format('F')}-{$date->year}";
    //         $results[$weekKey]['week'] = "Minggu {$weekNumber}";
    //         $results[$weekKey]['month'] = $date->format('F');
    //         $results[$weekKey]['year'] = $date->year;
    //         $results[$weekKey]['data'][] = $item->date;
    //     }

    //     return array_values($results);
    // }


}
