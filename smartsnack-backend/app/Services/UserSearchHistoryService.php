<?php

namespace App\Services;

use App\Repositories\UserSearchHistoryRepository;

class UserSearchHistoryService
{
    protected $searchHistoryRepo;

    public function __construct(UserSearchHistoryRepository $searchHistoryRepo)
    {
        $this->searchHistoryRepo = $searchHistoryRepo;
    }

    public function create(array $data)
    {
        return $this->searchHistoryRepo->create($data);
    }

    public function getByUserId(int $userId)
    {
        $items = $this->searchHistoryRepo->getByUserId($userId);

        if (!$items) {
            throw new \Exception('Produk tidak ditemukan.');
        }

        foreach ($items as $item) {
            $item->product->sugar_grade = sugarGrade(
                $item->product->category,
                $item->product->gr_sugar_content,
                $item->product->net_weight
            );
        }
        return $items;
    }

    public function exists(int $userId, int $productId): bool
    {
        return $this->searchHistoryRepo->exists($userId, $productId);
    }

    public function find(int $userId, int $productId)
    {
        return $this->searchHistoryRepo->find($userId, $productId);
    }

    public function touchCreatedAt($record)
    {
        return $this->searchHistoryRepo->updateCreatedAt($record);
    }
}
