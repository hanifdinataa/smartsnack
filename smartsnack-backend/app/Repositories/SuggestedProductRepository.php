<?php

namespace App\Repositories;

use App\Models\SuggestedProduct;

class SuggestedProductRepository
{

    public function create(array $data)
    {
        return SuggestedProduct::create($data);
    }

    public function getAllWithUser()
    {
        return SuggestedProduct::with('user')->orderBy('name', 'asc')->get();
    }
}
