<?php

namespace Database\Seeders;

use App\Models\Article;
use Illuminate\Database\Seeder;

class ArticleSeeder extends Seeder
{
    public function run(): void
    {
        $articles = [
            [
                'title' => 'Kenali Gejala Awal Diabetes pada Anak Sejak Dini',
                'excerpt' => 'Orang tua perlu mengenali tanda awal agar anak segera mendapat penanganan.',
                'content' => 'Gejala awal diabetes pada anak dapat berupa sering haus, sering buang air kecil, cepat lelah, dan berat badan menurun. Pada beberapa anak, gejala juga terlihat dari perubahan suasana hati dan menurunnya konsentrasi belajar. Jika gejala ini muncul terus-menerus, segera lakukan pemeriksaan gula darah. Penanganan cepat membantu mencegah komplikasi dan membuat kualitas hidup anak tetap baik.',
                'image' => 'https://images.unsplash.com/photo-1516627145497-ae6968895b74?auto=format&fit=crop&w=1200&q=80',
                'published_at' => now()->subDays(1),
            ],
            [
                'title' => 'Pola Makan Sehat untuk Anak dengan Risiko Diabetes',
                'excerpt' => 'Atur porsi, jadwal makan, dan pilihan camilan sehat untuk menjaga gula darah.',
                'content' => 'Anak dengan risiko diabetes tetap bisa menikmati makanan favorit dengan pengaturan porsi yang tepat. Prioritaskan makanan tinggi serat seperti sayur, buah utuh, dan sumber protein tanpa lemak. Batasi minuman manis kemasan, dan biasakan jadwal makan teratur agar lonjakan gula darah lebih terkendali. Libatkan anak saat memilih menu agar kebiasaan sehat lebih mudah diterapkan.',
                'image' => 'https://images.unsplash.com/photo-1543363136-31f0bb4d7dfb?auto=format&fit=crop&w=1200&q=80',
                'published_at' => now()->subDays(2),
            ],
            [
                'title' => 'Pentingnya Aktivitas Fisik Harian pada Anak',
                'excerpt' => 'Aktivitas fisik membantu sensitivitas insulin dan menjaga berat badan ideal.',
                'content' => 'Aktivitas fisik minimal 60 menit per hari sangat dianjurkan untuk anak. Bentuknya bisa bermain bola, bersepeda, menari, atau permainan aktif lain yang disukai. Gerak aktif membantu tubuh menggunakan glukosa lebih efektif, sekaligus mendukung kesehatan jantung. Orang tua dapat memulai dari kegiatan sederhana bersama keluarga agar anak merasa aktivitas fisik adalah hal menyenangkan.',
                'image' => 'https://images.unsplash.com/photo-1503454537195-1dcabb73ffb9?auto=format&fit=crop&w=1200&q=80',
                'published_at' => now()->subDays(3),
            ],
            [
                'title' => 'Membatasi Konsumsi Gula Tambahan pada Anak',
                'excerpt' => 'Langkah kecil sehari-hari dapat menurunkan asupan gula berlebih.',
                'content' => 'Gula tambahan sering tersembunyi pada minuman kemasan, sereal manis, dan camilan olahan. Orang tua bisa memulai dengan membiasakan air putih sebagai minuman utama dan mengganti camilan tinggi gula dengan buah atau yogurt tanpa tambahan gula. Membaca label gizi bersama anak juga membantu mereka memahami pilihan makanan yang lebih sehat.',
                'image' => 'https://images.unsplash.com/photo-1476234251651-f353703a034d?auto=format&fit=crop&w=1200&q=80',
                'published_at' => now()->subDays(4),
            ],
            [
                'title' => 'Peran Orang Tua dalam Kontrol Gula Darah Anak',
                'excerpt' => 'Dukungan keluarga berpengaruh besar pada keberhasilan kontrol diabetes anak.',
                'content' => 'Anak membutuhkan dukungan emosional dan rutinitas yang konsisten untuk mengelola gula darah. Orang tua dapat membuat jadwal makan, waktu aktivitas, dan waktu istirahat yang jelas. Catatan harian gula darah juga membantu evaluasi bersama tenaga kesehatan. Komunikasi yang positif membuat anak lebih percaya diri menjalani kebiasaan sehat.',
                'image' => 'https://images.unsplash.com/photo-1511895426328-dc8714191300?auto=format&fit=crop&w=1200&q=80',
                'published_at' => now()->subDays(5),
            ],
            [
                'title' => 'Bekal Sekolah Ramah Diabetes untuk Anak',
                'excerpt' => 'Bekal seimbang membantu anak tetap fokus belajar tanpa lonjakan gula berlebih.',
                'content' => 'Bekal sekolah sebaiknya berisi karbohidrat kompleks, protein, sayur, dan buah. Contohnya nasi merah porsi kecil, ayam panggang, tumis sayur, serta potongan apel. Hindari bekal yang terlalu manis atau tinggi tepung olahan. Dengan bekal yang tepat, energi anak lebih stabil selama di sekolah.',
                'image' => 'https://images.unsplash.com/photo-1509099836639-18ba1795216d?auto=format&fit=crop&w=1200&q=80',
                'published_at' => now()->subDays(6),
            ],
            [
                'title' => 'Kapan Anak Perlu Cek Gula Darah ke Dokter?',
                'excerpt' => 'Pemeriksaan dini penting jika ada gejala atau riwayat keluarga diabetes.',
                'content' => 'Jika anak menunjukkan gejala khas diabetes atau memiliki riwayat keluarga, konsultasi ke dokter sebaiknya tidak ditunda. Dokter akan menilai gejala, pola makan, aktivitas, dan menyarankan pemeriksaan laboratorium bila diperlukan. Pemeriksaan rutin membantu mendeteksi masalah lebih awal sehingga intervensi bisa dilakukan lebih cepat.',
                'image' => 'https://images.unsplash.com/photo-1579684288361-5c1a2951e0f0?auto=format&fit=crop&w=1200&q=80',
                'published_at' => now()->subDays(7),
            ],
            [
                'title' => 'Edukasi Anak Tentang Pilihan Minuman Sehat',
                'excerpt' => 'Ajari anak memilih minuman rendah gula dengan cara yang menyenangkan.',
                'content' => 'Mengganti minuman manis dengan air putih, susu tanpa gula tambahan, atau infused water dapat menurunkan asupan gula harian anak secara signifikan. Ajak anak memilih botol minum favorit dan jadikan kebiasaan minum air sebagai tantangan harian. Edukasi sederhana ini membantu anak membangun kebiasaan sehat jangka panjang.',
                'image' => 'https://images.unsplash.com/photo-1478147427282-58a87a120781?auto=format&fit=crop&w=1200&q=80',
                'published_at' => now()->subDays(8),
            ],
            [
                'title' => 'Tidur Cukup dan Dampaknya pada Gula Darah Anak',
                'excerpt' => 'Kurang tidur dapat memengaruhi metabolisme dan nafsu makan anak.',
                'content' => 'Anak usia sekolah membutuhkan tidur yang cukup agar metabolisme tubuh berjalan optimal. Kurang tidur sering memicu keinginan makan berlebih, terutama makanan manis. Buat rutinitas tidur yang konsisten, batasi layar sebelum tidur, dan ciptakan suasana kamar yang nyaman. Pola tidur baik mendukung kontrol gula darah yang lebih stabil.',
                'image' => 'https://images.unsplash.com/photo-1503454537195-1dcabb73ffb9?auto=format&fit=crop&w=1200&q=80',
                'published_at' => now()->subDays(9),
            ],
            [
                'title' => 'Dukungan Sekolah untuk Anak dengan Diabetes',
                'excerpt' => 'Kolaborasi orang tua dan sekolah penting untuk keamanan dan kenyamanan anak.',
                'content' => 'Sekolah perlu mengetahui kondisi kesehatan anak agar dapat membantu saat dibutuhkan. Orang tua dapat berdiskusi dengan wali kelas terkait jadwal makan, aktivitas fisik, dan tanda darurat yang perlu diperhatikan. Dengan dukungan lingkungan sekolah, anak dapat belajar dan beraktivitas dengan aman serta percaya diri.',
                'image' => 'https://images.unsplash.com/photo-1544717297-fa95b6ee9643?auto=format&fit=crop&w=1200&q=80',
                'published_at' => now()->subDays(10),
            ],
        ];

        Article::query()->delete();
        Article::query()->insert(
            array_map(static function (array $item): array {
                return [
                    ...$item,
                    'created_at' => now(),
                    'updated_at' => now(),
                ];
            }, $articles)
        );
    }
}
