<?php

use Illuminate\Support\Facades\Route;
use App\Http\Controllers\ProductController;
use App\Http\Controllers\ArticleController;

Route::redirect('/', '/products');

Route::delete('products', [ProductController::class, 'destroyAll'])->name('products.destroyAll');
Route::resource('products', ProductController::class);
Route::resource('articles', ArticleController::class);
