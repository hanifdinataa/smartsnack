<?php

namespace App\Repositories;

use App\Models\User;
use Illuminate\Support\Facades\Hash;

class UserRepository
{
    public function updateProfile(User $user, array $data)
    {
        if (isset($data['name'])) {
            $user->name = $data['name'];
        }

        if (isset($data['email'])) {
            $user->email = $data['email'];
        }

        if (!empty($data['password'])) {
            $user->password = Hash::make($data['password']);
        }

        if (isset($data['age'])) {
            $user->age = (int) $data['age'];
        }

        if (isset($data['gender'])) {
            $user->gender = $data['gender'];
        }

        $user->save();

        return $user;
    }
}
