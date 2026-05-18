<?php

namespace App\Http\Controllers\API;

use App\Http\Controllers\Controller;
use App\Models\Article;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ArticleController extends Controller
{
    // Alur fungsi ini: app minta daftar artikel, backend query artikel terbaru dari database, lalu kirim list JSON ke aplikasi.
    public function index(): JsonResponse
    {
        $articles = Article::query()
            ->orderByDesc('published_at')
            ->orderByDesc('id')
            ->get();

        return successResponse($articles, 'Daftar artikel berhasil diambil.');
    }

    // Alur fungsi ini: app minta detail artikel berdasarkan ID, backend ambil data artikel + rekomendasi, lalu kirim response JSON.
    public function show(int $id): JsonResponse
    {
        $article = Article::find($id);
        if (!$article) {
            return errorResponse('Artikel tidak ditemukan.', null, 404);
        }

        $recommended = Article::query()
            ->where('id', '!=', $article->id)
            ->orderByDesc('published_at')
            ->orderByDesc('id')
            ->limit(4)
            ->get();

        return successResponse([
            'article' => $article,
            'recommended_articles' => $recommended,
        ], 'Detail artikel berhasil diambil.');
    }

    // Alur fungsi ini: app kirim data artikel baru, backend validasi dan simpan ke database, lalu kirim data artikel yang sudah dibuat.
    public function store(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'title' => 'required|string|max:255',
            'excerpt' => 'nullable|string',
            'content' => 'required|string',
            'image' => 'nullable|image|max:10240',
            'image_url' => 'nullable|string|max:2048',
            'published_at' => 'nullable|date',
        ]);

        $image = $this->resolveImage($request, null, (string) ($validated['image_url'] ?? ''));

        $article = Article::create([
            'title' => (string) $validated['title'],
            'excerpt' => (string) ($validated['excerpt'] ?? ''),
            'content' => (string) $validated['content'],
            'image' => $image,
            'published_at' => $validated['published_at'] ?? now(),
        ]);

        return successResponse($article, 'Artikel berhasil dibuat.', 201);
    }

    // Alur fungsi ini: app kirim perubahan artikel berdasarkan ID, backend validasi lalu update ke database, kemudian kirim data terbaru.
    public function update(Request $request, int $id): JsonResponse
    {
        $article = Article::find($id);
        if (!$article) {
            return errorResponse('Artikel tidak ditemukan.', null, 404);
        }

        $validated = $request->validate([
            'title' => 'sometimes|required|string|max:255',
            'excerpt' => 'nullable|string',
            'content' => 'sometimes|required|string',
            'image' => 'nullable|image|max:10240',
            'image_url' => 'nullable|string|max:2048',
            'published_at' => 'nullable|date',
        ]);

        $image = $this->resolveImage($request, $article->image, (string) ($validated['image_url'] ?? ''));

        $article->update([
            'title' => array_key_exists('title', $validated) ? (string) $validated['title'] : $article->title,
            'excerpt' => array_key_exists('excerpt', $validated) ? (string) ($validated['excerpt'] ?? '') : $article->excerpt,
            'content' => array_key_exists('content', $validated) ? (string) $validated['content'] : $article->content,
            'image' => $image,
            'published_at' => array_key_exists('published_at', $validated) ? ($validated['published_at'] ?? now()) : $article->published_at,
        ]);

        return successResponse($article->fresh(), 'Artikel berhasil diperbarui.');
    }

    // Alur fungsi ini: app kirim ID artikel yang mau dihapus, backend hapus dari database, lalu kirim status sukses.
    public function destroy(int $id): JsonResponse
    {
        $article = Article::find($id);
        if (!$article) {
            return errorResponse('Artikel tidak ditemukan.', null, 404);
        }

        $article->delete();
        return successResponse(null, 'Artikel berhasil dihapus.');
    }

    private function resolveImage(Request $request, ?string $currentImage, string $fallbackUrl): string
    {
        if ($request->hasFile('image')) {
            $path = $request->file('image')->store('articles', 'public');
            return url('storage/' . $path);
        }

        if (trim($fallbackUrl) !== '') {
            return trim($fallbackUrl);
        }

        return (string) ($currentImage ?? '');
    }
}
