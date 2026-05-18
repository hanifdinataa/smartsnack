<!-- # SugarCare Flutter

Migrasi SugarCareApp (Android Native) ke Flutter dengan struktur sederhana.

## Struktur `lib/` (simple)

- `main.dart`: inisialisasi app + theme + session gate.
- `models/`: model request/response API.
- `services/`: API client, local storage, image classifier.
- `providers/`: Riverpod state (session/auth).
- `pages/`: semua screen utama aplikasi.
- `widgets/`: komponen reusable.

## Catatan

- Backend tetap menggunakan Laravel endpoint yang sama (`/api/...`).
- Asset visual, font, dan model TFLite native sudah disalin ke folder `assets/`.

## Jalankan Backend + Flutter Web

1. Jalankan backend Laravel:
   - `cd ../sugarcare-backend`
   - `php artisan optimize:clear`
   - `php artisan serve --host=127.0.0.1 --port=8000`
2. Jalankan Flutter web:
   - `cd ../sugarcare_flutter`
   - `flutter pub get`
   - `flutter run -d chrome`

Default Flutter Web sekarang otomatis memakai API `http://127.0.0.1:8000`.
Kalau mau ganti endpoint, gunakan:
- `flutter run -d chrome --dart-define=API_BASE_URL=http://alamat-api-kamu`

## Jalankan Di HP Android (Debug)

1. Jalankan backend di laptop:
   - `cd ../sugarcare-backend`
   - `php artisan serve --host=0.0.0.0 --port=8000`
2. Sambungkan HP via USB dan aktifkan USB debugging.
3. Jalankan reverse port (supaya HP bisa akses backend laptop via `127.0.0.1`):
   - `adb reverse tcp:8000 tcp:8000`
4. Jalankan Flutter:
   - `flutter run -d <device_id> --dart-define=API_BASE_URL=http://127.0.0.1:8000`

Alternatif tanpa USB reverse (pakai Wi-Fi sama):
- `flutter run -d <device_id> --dart-define=API_BASE_URL=http://IP_LAPTOP:8000`

## Catatan Klasifikasi Kamera / Upload

- Flutter Web sekarang tidak lagi dipaksa Android untuk fitur kamera/upload.
- Alur klasifikasi web sekarang lewat endpoint backend: `POST /api/classify-product`.
- Backend sudah disiapkan 2 mode:
  - `xgboost_service` (jika kamu set `ML_XGBOOST_ENDPOINT`)
  - `image_hash_fallback` (fallback sementara agar fitur tetap jalan) -->
