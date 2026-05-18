@extends('layouts.app')

@section('content')
<div class="container">
    <h2>Edit Article</h2>
    <a href="{{ route('articles.index') }}" class="btn btn-secondary mb-3">Back</a>

    @if ($errors->any())
        <div class="alert alert-danger">
            <ul class="mb-0">
                @foreach ($errors->all() as $error)
                    <li>{{ $error }}</li>
                @endforeach
            </ul>
        </div>
    @endif

    <form action="{{ route('articles.update', $article->id) }}" method="POST" enctype="multipart/form-data">
        @csrf
        @method('PUT')
        <div class="mb-3">
            <label class="form-label">Title</label>
            <input type="text" name="title" class="form-control" value="{{ old('title', $article->title) }}" required>
        </div>
        <div class="mb-3">
            <label class="form-label">Excerpt</label>
            <textarea name="excerpt" class="form-control" rows="2">{{ old('excerpt', $article->excerpt) }}</textarea>
        </div>
        <div class="mb-3">
            <label class="form-label">Content</label>
            <textarea name="content" class="form-control" rows="8" required>{{ old('content', $article->content) }}</textarea>
        </div>
        <div class="mb-3">
            <label class="form-label">Image Upload</label>
            <input type="file" name="image" class="form-control" accept="image/*">
            @if($article->image)
                <img src="{{ $article->image }}" alt="article image" style="width:160px;height:100px;object-fit:cover;margin-top:10px;border-radius:8px;">
            @endif
        </div>
        <div class="mb-3">
            <label class="form-label">Image URL (optional)</label>
            <input type="text" name="image_url" class="form-control" value="{{ old('image_url') }}">
        </div>
        <div class="mb-3">
            <label class="form-label">Published At</label>
            <input type="datetime-local" name="published_at" class="form-control" value="{{ old('published_at', optional($article->published_at)->format('Y-m-d\TH:i')) }}">
        </div>
        <button class="btn btn-primary">Update</button>
    </form>
</div>
@endsection

