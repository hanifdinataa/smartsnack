<?php

namespace App\Repositories;

use App\Models\UserSearchHistory;

//search product
class UserSearchHistoryRepository
{
    public function create(array $data)
    {
        return UserSearchHistory::create($data);
    }

    public function getByUserId(int $userId)
    {
        return UserSearchHistory::where('user_id', $userId)
            ->with('product')
            ->orderBy('created_at', 'desc')
            ->get();
    }

    public function exists(int $userId, int $productId): bool
    {
        return UserSearchHistory::where('user_id', $userId)
            ->where('product_id', $productId)
            ->exists();
    }

    public function find(int $userId, int $productId)
    {
        return UserSearchHistory::where('user_id', $userId)
            ->where('product_id', $productId)
            ->first();
    }

    public function updateCreatedAt($record)
    {
        $record->created_at = now();
        $record->save(['timestamps' => false]); 
        return $record;
    }
}
