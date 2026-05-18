<?php

namespace App\Http\Controllers\API;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Http\Requests\StoreSuggestedProductRequest;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Str;
use App\Services\SuggestedProductService;



class SuggestedProductController extends Controller
{
    protected $sProductService;



    public function __construct(SuggestedProductService $sProductService)
    {
        $this->sProductService = $sProductService;
    }






    // Alur fungsi ini: request dari app diproses di controller (validasi + service/model/database), lalu response dikirim balik ke aplikasi.
    public function store(StoreSuggestedProductRequest $request): JsonResponse
    {
        $data = $request->validated();

        $imagePath = null;
        if ($request->hasFile('image')) {
            $image = $request->file('image');
            $filename = Str::uuid() . '.' . $image->getClientOriginalExtension();
            $imagePath = $image->storeAs('images', $filename, 'public');
        }

        $data['user_id'] = auth('sanctum')->id();
        $data['name'] = $request->name;
        $data['category'] = $request->category;
        $data['image'] = $imagePath;
        $data['gr_sugar_content'] = $request->gr_sugar_content;
        $data['net_weight'] = $request->net_weight;
        $data['servings_per_package'] = $request->servings_per_package;
        $data['serving_size_ml'] = $request->serving_size_ml;

        $this->sProductService->create($data);
        return successResponse($data, "Suggested Product created successfully");
    }
}


