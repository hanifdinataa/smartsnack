<?php

namespace App\Http\Controllers\API;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Services\UserService;
use App\Http\Requests\UpdateUserProfileRequest;

class UserController extends Controller
{
    protected $service;



    public function __construct(UserService $service)
    {
        $this->service = $service;
    }






    // Alur fungsi ini: request dari app diproses di controller (validasi + service/model/database), lalu response dikirim balik ke aplikasi.
    public function update(UpdateUserProfileRequest $request)
    {
        // Validasi otomatis terjadi saat form request dipanggil
        $validatedData = $request->validated();
        if ($validatedData) {
            $user = $request->user();
            $updatedUser = $this->service->updateProfile($user, $validatedData);
            return successResponse($updatedUser, 'Profil berhasil diperbarui.');
        } else {
            return response()->json([
                'success' => false,
                'message' => 'Validasi gagal.',
            ], 422);
        }
    }












    // Alur fungsi ini: request dari app diproses di controller (validasi + service/model/database), lalu response dikirim balik ke aplikasi.
    public function profile(Request $request)
    {
        return successResponse($request->user(), "User detail");
    }
}


