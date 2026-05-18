<?php

namespace App\Http\Controllers\API;

use Illuminate\Http\Request;
use App\Http\Controllers\Controller;
use App\Services\UserSearchHistoryService;
use Illuminate\Http\JsonResponse;
use App\Http\Resources\UserProductHistorySearchResource;

class UserSearchHistoryController extends Controller
{
    protected $searchHistoryService;

    public  function __construct(UserSearchHistoryService $searchHistoryService)
    {
        $this->searchHistoryService = $searchHistoryService;
    }






    // Alur fungsi ini: request dari app diproses di controller (validasi + service/model/database), lalu response dikirim balik ke aplikasi.
    public function index(): JsonResponse
    {
        $userId = auth('sanctum')->id();
        $data = $this->searchHistoryService->getByUserId($userId);

        return successResponse(UserProductHistorySearchResource::collection($data), 'User search history successfully retrieved.');
    }






    // Alur fungsi ini: request dari app diproses di controller (validasi + service/model/database), lalu response dikirim balik ke aplikasi.
    public function store(Request $request)
    {
        $request->validate([
            'product_id' => 'required|exists:products,id',
        ]);

        $userId = auth('sanctum')->id();
        $productId = $request->product_id;

        $existingRecord = $this->searchHistoryService->find($userId, $productId);

        if ($existingRecord) {
            $this->searchHistoryService->touchCreatedAt($existingRecord);
            return successResponse(null, "Record timestamp updated");
        }

        $data = [
            'user_id' => $userId,
            'product_id' => $productId,
        ];

        $this->searchHistoryService->create($data);
        return successResponse($data, "User consumption record created successfully");
    }
}


