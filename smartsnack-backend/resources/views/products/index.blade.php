@extends('layouts.app')

@section('content')
<div class="container">
    <h2>Product List</h2>
    <a href="{{ route('products.create') }}" class="btn btn-primary mb-3">Add Product</a>
    <a href="{{ route('articles.index') }}" class="btn btn-dark mb-3">Articles</a>
    <form action="{{ route('products.destroyAll') }}" method="POST" class="d-inline">
        @csrf
        @method('DELETE')
        <button
            type="submit"
            class="btn btn-danger mb-3"
            onclick="return confirm('Yakin ingin menghapus SEMUA produk? Aksi ini tidak bisa dibatalkan.');"
        >
            Hapus All Product
        </button>
    </form>

    @if (session('success'))
        <div class="alert alert-success">{{ session('success') }}</div>
    @endif

    <table class="table table-bordered">
        <thead>
            <tr>
                <th>Name</th>
                <th>Category</th>
                <th>Net Weight</th>
                <th>Sugar (g)</th>
                <th>Actions</th>
            </tr>
        </thead>
        <tbody>
            @foreach($products as $product)
            <tr>
                <td>{{ $product->name }}</td>
                <td>{{ ucfirst($product->category) }}</td>
                <td>{{ $product->net_weight }} g</td>
                <td>{{ $product->gr_sugar_content }}</td>
                <td>
                    <a href="{{ route('products.show', $product->id) }}" class="btn btn-info btn-sm">View</a>
                    <a href="{{ route('products.edit', $product) }}" class="btn btn-sm btn-warning">Edit</a>
                    <form action="{{ route('products.destroy', $product) }}" method="POST" class="d-inline">
                        @csrf @method('DELETE')
                        <button class="btn btn-sm btn-danger" onclick="return confirm('Are you sure?')">Delete</button>
                    </form>
                </td>
            </tr>
            @endforeach
        </tbody>
    </table>
</div>
@endsection
