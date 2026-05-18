@extends('layouts.app')

@section('content')
<div class="container">
    <a href="{{ route('articles.index') }}" class="btn btn-secondary mb-3">Back</a>
    <h2>{{ $article->title }}</h2>
    <p class="text-muted">{{ optional($article->published_at)->format('Y-m-d H:i') }}</p>
    @if($article->image)
        <img src="{{ $article->image }}" alt="article image" style="max-width:100%;max-height:320px;object-fit:cover;border-radius:10px;">
    @endif
    @if($article->excerpt)
        <p class="mt-3"><strong>{{ $article->excerpt }}</strong></p>
    @endif
    <div class="mt-3" style="white-space: pre-line;">{{ $article->content }}</div>
</div>
@endsection

