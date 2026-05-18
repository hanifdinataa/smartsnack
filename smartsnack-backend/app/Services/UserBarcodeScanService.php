<?php

namespace App\Services;

use App\Repositories\UserBarcodeScanRepository;

class UserBarcodeScanService
{
    public function __construct(private readonly UserBarcodeScanRepository $repository)
    {
    }

    public function create(array $data)
    {
        return $this->repository->create($data);
    }
}
