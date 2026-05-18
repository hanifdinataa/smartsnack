<?php

namespace App\Repositories;

use App\Models\Product;

class ProductRepository
{
    public function searchByName(string $keyword)
    {
        return Product::where('name', 'like', "%{$keyword}%")
            ->select('id', 'name', 'image', 'gr_sugar_content', 'net_weight', 'category')
            ->get();
    }

    public function allWithVarians()
    {
        return Product::orderBy('name', 'asc')->get();
    }

    public function create(array $data)
    {
        return Product::create($data);
    }

    public function update(Product $product, array $data)
    {
        $fresh = Product::findOrFail($product->id);
        $fresh->update($data);
        return $fresh;
    }

    public function delete(Product $product)
    {
        return $product->delete();
    }

    public function findProductById(int $id)
    {
        return Product::findOrFail($id);
    }

    public function findByBarcode(string $barcode)
    {
        return Product::where('barcode', $barcode)->first();
    }

    public function findByIdWithVarians(int $id)
    {
        return Product::find($id);
    }

    public function getAllForLabelMatching()
    {
        return Product::select('id', 'name', 'category', 'image', 'gr_sugar_content', 'net_weight')
            ->orderBy('name', 'asc')
            ->get();
    }

    public function findProductCategoryById(int $id)
    {
        return Product::where('id', $id)->pluck('category')->first();
    }

    public function findSugarProductById(int $id)
    {
        return Product::where('id', $id)->pluck('gr_sugar_content')->first();
    }

    public function findNetWeightById(int $id)
    {
        return Product::where('id', $id)->pluck('net_weight')->first();
    }

    public function findProductNameById(int $id)
    {
        return Product::where('id', $id)->pluck('name')->first();
    }


    public function getProductImgById(int $id)
    {
        return Product::where('id', $id)->pluck('image')->first();
    }

    public function getSameVarianProduct(string $category, int $excludeId)
    {
        return Product::where('id', '!=', $excludeId)
            ->where('category', $category)
            ->get();
    }
}
