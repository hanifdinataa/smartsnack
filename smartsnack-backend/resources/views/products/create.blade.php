@extends('layouts.app')

@section('content')
<div class="container">
    <h2>Create Product</h2>
    <form method="POST" action="{{ route('products.store') }}">
        @csrf

        <div class="mb-3">
            <label class="form-label">Product Name</label>
            <input type="text" name="name" class="form-control" required>
        </div>

        <div class="mb-3">
            <label class="form-label">Category</label>
            <select name="category" class="form-select" required>
                <option value="">-- Select Category --</option>
                <option value="food">Food</option>
                <option value="drink">Drink</option>
            </select>
        </div>

        <div class="mb-3">
            <label class="form-label">Image URL (optional)</label>
            <input type="text" name="image" class="form-control">
        </div>

        <div class="mb-3">
            <label class="form-label">Sugar Content (gram)</label>
            <input type="number" step="0.01" name="gr_sugar_content" class="form-control" required>
        </div>

        <div class="mb-3">
            <label class="form-label">Net Weight</label>
            <input type="number" step="0.01" name="net_weight" class="form-control" required>
        </div>

        <button type="submit" class="btn btn-primary">Save Product</button>
    </form>
</div>
@endsection
