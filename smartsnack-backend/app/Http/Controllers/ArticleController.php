<?php

namespace App\Http\Controllers;

use App\Models\Article;
use Illuminate\Http\Request;

class ArticleController extends Controller
{
    // Alur fungsi ini: request masuk dari frontend/web, backend ambil daftar artikel dari database, lalu kirim ke halaman list.
    public function index()
    {
        $articles = Article::query()
            ->orderByDesc('published_at')
            ->orderByDesc('id')
            ->get();

        return view('articles.index', compact('articles'));
    }

    // Alur fungsi ini: request masuk dari frontend/web, backend tampilkan form tambah artikel.
    public function create()
    {
        return view('articles.create');
    }

    // Alur fungsi ini: request masuk dari frontend/web, backend validasi input artikel lalu simpan ke database, kemudian redirect dengan status sukses.
    public function store(Request $request)
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

        Article::create([
            'title' => (string) $validated['title'],
            'excerpt' => (string) ($validated['excerpt'] ?? ''),
            'content' => (string) $validated['content'],
            'image' => $image,
            'published_at' => $validated['published_at'] ?? now(),
        ]);

        return redirect()->route('articles.index')->with('success', 'Artikel berhasil dibuat.');
    }

    // Alur fungsi ini: request masuk dari frontend/web, backend ambil detail artikel berdasarkan ID, lalu tampilkan ke halaman detail.
    public function show(int $id)
    {
        $article = Article::findOrFail($id);
        return view('articles.show', compact('article'));
    }

    // Alur fungsi ini: request masuk dari frontend/web, backend ambil artikel berdasarkan ID, lalu tampilkan form edit.
    public function edit(int $id)
    {
        $article = Article::findOrFail($id);
        return view('articles.edit', compact('article'));
    }

    // Alur fungsi ini: request masuk dari frontend/web, backend validasi perubahan artikel lalu update ke database, kemudian redirect dengan status sukses.
    public function update(Request $request, int $id)
    {
        $article = Article::findOrFail($id);

        $validated = $request->validate([
            'title' => 'required|string|max:255',
            'excerpt' => 'nullable|string',
            'content' => 'required|string',
            'image' => 'nullable|image|max:10240',
            'image_url' => 'nullable|string|max:2048',
            'published_at' => 'nullable|date',
        ]);

        $image = $this->resolveImage($request, $article->image, (string) ($validated['image_url'] ?? ''));

        $article->update([
            'title' => (string) $validated['title'],
            'excerpt' => (string) ($validated['excerpt'] ?? ''),
            'content' => (string) $validated['content'],
            'image' => $image,
            'published_at' => $validated['published_at'] ?? now(),
        ]);

        return redirect()->route('articles.index')->with('success', 'Artikel berhasil diperbarui.');
    }

    // Alur fungsi ini: request masuk dari frontend/web, backend hapus artikel target dari database, lalu redirect dengan pesan berhasil.
    public function destroy(int $id)
    {
        $article = Article::findOrFail($id);
        $article->delete();
        return redirect()->route('articles.index')->with('success', 'Artikel berhasil dihapus.');
    }

    private function resolveImage(Request $request, ?string $currentImage, string $fallbackUrl): string
    {
        if ($request->hasFile('image')) {
            $path = $request->file('image')->store('articles', 'public');
            return url('storage/' . $path);
        }

        $fallback = trim($fallbackUrl);
        if ($fallback !== '') {
            return $fallback;
        }

        return (string) ($currentImage ?? '');
    }
}
