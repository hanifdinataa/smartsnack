<?php

namespace App\Services;

use App\Repositories\SuggestedProductRepository;

class SuggestedProductService
{
    protected $sProductRepo;

    public function __construct(SuggestedProductRepository $sProductRepo)
    {
        $this->sProductRepo = $sProductRepo;
    }

    public function getAllWithUser()
    {
        return $this->sProductRepo->getAllWithUser();
    }


    public function create(array $data)
    {
        return $this->sProductRepo->create($data);
    }
}
