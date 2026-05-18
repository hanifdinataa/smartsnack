<?php

namespace App\Repositories;

use App\Models\UserBarcodeScan;

class UserBarcodeScanRepository
{
    public function create(array $data)
    {
        return UserBarcodeScan::create($data);
    }
}
