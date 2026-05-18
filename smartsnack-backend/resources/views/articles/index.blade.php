@extends('layouts.app')

@section('content')
<div class="container">
    <h2>Article List</h2>
    <a href="{{ route('articles.create') }}" class="btn btn-primary mb-3">Add Article</a>
    <a href="{{ route('products.index') }}" class="btn btn-secondary mb-3">Products</a>

    @if (session('success'))
        <div class="alert alert-success">{{ session('success') }}</div>
    @endif

    <table class="table table-bordered">
        <thead>
            <tr>
                <th style="width: 90px;">Image</th>
                <th>Title</th>
                <th>Published At</th>
                <th>Actions</th>
            </tr>
        </thead>
        <tbody>
            @forelse($articles as $article)
                <tr>
                    <td>
                        @if($article->image)
                            <img src="{{ $article->image }}" alt="image" style="width:70px;height:70px;object-fit:cover;border-radius:8px;">
                        @endif
                    </td>
                    <td>{{ $article->title }}</td>
                    <td>{{ optional($article->published_at)->format('Y-m-d H:i') }}</td>
                    <td>
                        <a href="{{ route('articles.show', $article->id) }}" class="btn btn-info btn-sm">View</a>
                        <a href="{{ route('articles.edit', $article->id) }}" class="btn btn-warning btn-sm">Edit</a>
                        <form action="{{ route('articles.destroy', $article->id) }}" method="POST" class="d-inline">
                            @csrf
                            @method('DELETE')
                            <button class="btn btn-danger btn-sm" onclick="return confirm('Delete this article?')">Delete</button>
                        </form>
                    </td>
                </tr>
            @empty
                <tr><td colspan="4" class="text-center">Belum ada artikel.</td></tr>
            @endforelse
        </tbody>
    </table>
</div>
@endsection

