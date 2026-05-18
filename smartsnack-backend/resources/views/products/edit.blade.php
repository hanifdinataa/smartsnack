@extends('layouts.app')

@section('content')
    <div class="container">
        <h2>Edit Product</h2>
        <form method="POST" action="{{ route('products.update', $product->id) }}" enctype="multipart/form-data">

            @csrf
            @method('PUT')

            <div class="mb-3">
                <label class="form-label">Product Name</label>
                <input type="text" name="name" value="{{ $product->name }}" class="form-control" required>
            </div>

            <div class="mb-3">
                <label class="form-label">Category</label>
                <select name="category" class="form-select" required>
                    <option value="food" {{ $product->category === 'food' ? 'selected' : '' }}>Food</option>
                    <option value="drink" {{ $product->category === 'drink' ? 'selected' : '' }}>Drink</option>
                </select>
            </div>

            <div class="mb-3">
                <label class="form-label">Image URL</label>
                <input type="text" name="image" value="{{ $product->image }}" class="form-control">
            </div>

            <div class="mb-3">
                <label class="form-label">Sugar Content (gram)</label>
                <input type="number" step="0.01" name="gr_sugar_content" value="{{ $product->gr_sugar_content }}"
                    class="form-control" required>
            </div>

            <div class="mb-3">
                <label class="form-label">Net Weight (gram)</label>
                <input type="number" step="0.01" name="net_weight" value="{{ $product->net_weight }}"
                    class="form-control" required>
            </div>

            <button type="submit" class="btn btn-primary">Update Product</button>
        </form>
    </div>
@endsection
