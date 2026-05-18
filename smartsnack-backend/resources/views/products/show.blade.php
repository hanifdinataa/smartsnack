@php
    use Illuminate\Support\Str;
@endphp

@extends('layouts.app')

@section('content')
    <div class="container">
        <h2>Product Detail</h2>

        <div class="card mb-3" style="max-width: 540px;">
            <div class="row g-0">
                <div class="col-md-4">
                    <img src="{{ $product->image }}" class="img-fluid" alt="Product Image">
                </div>

                <div class="col-md-8">
                    <div class="card-body">
                        <h5 class="card-title">{{ $product->name }}</h5>
                        <p class="card-text"><strong>Category:</strong> {{ ucfirst($product->category) }}</p>
                        <p class="card-text"><strong>Sugar Content:</strong> {{ $product->gr_sugar_content }} gr</p>
                        <p class="card-text"><strong>Net Weight:</strong> {{ $product->net_weight }} gr</p>

                        <p class="card-text">
                            <strong>Image URL:</strong>
                            @if ($product->image)
                                <a href="{{ $product->image }}" target="_blank">{{ $product->image }}</a>
                            @else
                                <span class="text-muted">No image URL</span>
                            @endif
                        </p>

                        <a href="{{ route('products.index') }}" class="btn btn-secondary">Back</a>
                    </div>
                </div>
            </div>
        </div>
    </div>
@endsection
