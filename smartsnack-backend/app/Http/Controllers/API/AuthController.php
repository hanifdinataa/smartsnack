<?php

namespace App\Http\Controllers\API;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Support\Facades\Hash;
use App\Http\Requests\RegisterRequest;
use App\Http\Requests\LoginRequest;
use Illuminate\Http\Request;


class AuthController extends Controller
{
    // Alur fungsi ini: app kirim data registrasi, backend validasi lalu simpan user baru, generate token, dan kirim user+token ke aplikasi.
    public function register(RegisterRequest $request)
    {
        $user = User::create([
            'name'     => $request->name,
            'email'    => $request->email,
            'password' => Hash::make($request->password),
        ]);

        $token = $user->createToken('auth_token')->plainTextToken;


        return successResponse([
            'user'  => $user,
            'token' => $token
        ], 'User registered successfully');
    }



    // Alur fungsi ini: app kirim email/password, backend validasi kredensial user, generate token login, lalu kirim hasil autentikasi.
    public function login(LoginRequest $request)
    {
        $user = User::where('email', $request->email)->first();

        if (!$user || !Hash::check($request->password, $user->password)) {
            return errorResponse('Email atau password salah.', null, 401);
        }

        $token = $user->createToken('auth_token')->plainTextToken;

        return successResponse([
            'user'  => $user,
            'token' => $token
        ], 'Login successful');
    }




    // Alur fungsi ini: app kirim token aktif, backend hapus token user agar sesi API private berakhir.
    public function logout(Request $request)
    {
        $request->user()->tokens->each(function ($token) {
            $token->delete();
        });

        return successResponse(null, 'Logged out successfully');
    }
}


