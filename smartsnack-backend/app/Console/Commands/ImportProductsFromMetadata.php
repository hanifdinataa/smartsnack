<?php

namespace App\Console\Commands;

use App\Models\Product;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Storage;

class ImportProductsFromMetadata extends Command
{
    protected $signature = 'products:import-metadata
        {--csv=storage/app/import/products_from_labels.csv : Path CSV metadata}
        {--images-root=../MODEL/product-images : Root folder images product}
        {--copy-images : Copy image files into storage/app/public/products}
        {--dry-run : Validate and preview without writing DB}';

    protected $description = 'Import products from CSV metadata (name, sugar, serving size, image) into products table';

    public function handle(): int
    {
        $csvPath = base_path($this->option('csv'));
        $imagesRoot = base_path($this->option('images-root'));
        $dryRun = (bool) $this->option('dry-run');
        $copyImages = (bool) $this->option('copy-images');

        if (!is_file($csvPath)) {
            $this->error("CSV not found: {$csvPath}");
            return self::FAILURE;
        }

        $fp = fopen($csvPath, 'r');
        if ($fp === false) {
            $this->error("Cannot open CSV: {$csvPath}");
            return self::FAILURE;
        }

        $headers = fgetcsv($fp);
        if (!$headers) {
            fclose($fp);
            $this->error('CSV header is empty.');
            return self::FAILURE;
        }

        $headers = array_map(function ($h) {
            $h = trim((string) $h);
            $h = preg_replace('/^\xEF\xBB\xBF/', '', $h) ?? $h;
            $h = trim($h, "\"' \t\n\r\0\x0B");
            return strtolower($h);
        }, $headers);
        $required = ['name', 'category', 'filename', 'gr_sugar_content', 'net_weight', 'serving_size'];
        foreach ($required as $key) {
            if (!in_array($key, $headers, true)) {
                fclose($fp);
                $this->error("Missing required column: {$key}");
                return self::FAILURE;
            }
        }

        $idx = array_flip($headers);
        $total = 0;
        $upserted = 0;
        $skipped = 0;

        while (($row = fgetcsv($fp)) !== false) {
            $total++;
            $name = trim((string) ($row[$idx['name']] ?? ''));
            $category = strtolower(trim((string) ($row[$idx['category']] ?? '')));
            $filename = trim((string) ($row[$idx['filename']] ?? ''));
            $sugarRaw = trim((string) ($row[$idx['gr_sugar_content']] ?? ''));
            $netWeightRaw = trim((string) ($row[$idx['net_weight']] ?? ''));
            $servingRaw = trim((string) ($row[$idx['serving_size']] ?? ''));

            if ($name === '' || $filename === '' || !in_array($category, ['food', 'drink'], true)) {
                $skipped++;
                continue;
            }

            $sugar = is_numeric($sugarRaw) ? (float) $sugarRaw : 0.0;
            $netWeight = is_numeric($netWeightRaw) ? (float) $netWeightRaw : 0.0;
            $servingSize = is_numeric($servingRaw) ? (float) $servingRaw : 0.0;

            $imageRelative = $this->resolveImagePath($imagesRoot, $category, $filename, $name, $copyImages);
            if ($imageRelative === null) {
                $skipped++;
                $this->warn("Image not found for: {$name} ({$category}/{$filename})");
                continue;
            }

            if ($dryRun) {
                $upserted++;
                continue;
            }

            Product::updateOrCreate(
                ['name' => $name],
                [
                    'category' => $category,
                    'image' => $imageRelative,
                    'gr_sugar_content' => $sugar,
                    'net_weight' => $netWeight,
                    'serving_size' => $servingSize,
                ]
            );
            $upserted++;
        }

        fclose($fp);

        $this->info("Rows read: {$total}");
        $this->info("Imported/updated: {$upserted}");
        $this->info("Skipped: {$skipped}");
        if ($dryRun) {
            $this->comment('Dry run only. No DB writes were made.');
        }

        return self::SUCCESS;
    }

    private function resolveImagePath(string $imagesRoot, string $category, string $filename, string $name, bool $copyImages): ?string
    {
        $categoryDir = rtrim($imagesRoot, '\\/') . DIRECTORY_SEPARATOR . $category;
        $sourcePath = $categoryDir . DIRECTORY_SEPARATOR . $filename;
        if (!is_file($sourcePath)) {
            $sourcePath = $this->findImageByNameFallback($categoryDir, $name, $filename);
            if ($sourcePath === null) {
                return null;
            }
        }

        if (!$copyImages) {
            return str_replace('\\', '/', $sourcePath);
        }

        $targetRelative = 'products/' . $filename;
        $targetDiskPath = Storage::disk('public')->path($targetRelative);
        $targetDir = dirname($targetDiskPath);
        if (!is_dir($targetDir)) {
            mkdir($targetDir, 0777, true);
        }
        copy($sourcePath, $targetDiskPath);

        return 'storage/' . $targetRelative;
    }

    private function findImageByNameFallback(string $categoryDir, string $name, string $filename): ?string
    {
        if (!is_dir($categoryDir)) {
            return null;
        }

        $nameNorm = $this->normalize($name);
        $filenameStemNorm = $this->normalize(pathinfo($filename, PATHINFO_FILENAME));
        $files = glob($categoryDir . DIRECTORY_SEPARATOR . '*.{jpg,jpeg,png,JPG,JPEG,PNG}', GLOB_BRACE) ?: [];

        foreach ($files as $file) {
            $baseNorm = $this->normalize(pathinfo($file, PATHINFO_FILENAME));
            if ($baseNorm === $nameNorm || str_contains($baseNorm, $nameNorm) || str_contains($nameNorm, $baseNorm)) {
                return $file;
            }
            if ($filenameStemNorm !== '' && (str_contains($baseNorm, $filenameStemNorm) || str_contains($filenameStemNorm, $baseNorm))) {
                return $file;
            }
        }

        return null;
    }

    private function normalize(string $value): string
    {
        $value = strtolower($value);
        return preg_replace('/[^a-z0-9]+/', '', $value) ?? '';
    }
}
