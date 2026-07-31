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
                'title' => 'Pentingnya Memantau Detak Jantung Anak Saat Beraktivitas',
                'excerpt' => 'Detak jantung yang sehat mencerminkan kondisi fisik dan kebugaran yang prima.',
                'content' => 'Detak jantung istirahat (resting heart rate) normal untuk anak usia sekolah umumnya berada pada rentang 70-110 bpm. Memantau detak jantung secara berkala dapat membantu mendeteksi anomali pada kebugaran atau tingkat stres fisik mereka. Pastikan anak tidak terlalu kelelahan dan memiliki waktu istirahat yang cukup setiap harinya.',
                'image' => 'https://images.unsplash.com/photo-1516627145497-ae6968895b74?auto=format&fit=crop&w=1200&q=80',
                'published_at' => now()->subDays(1),
            ],
            [
                'title' => 'Suhu Tubuh Normal pada Anak dan Kapan Harus Waspada',
                'excerpt' => 'Suhu tubuh merupakan indikator awal adanya infeksi atau masalah kesehatan.',
                'content' => 'Suhu tubuh normal anak berkisar antara 36.0 hingga 37.5 °C. Jika suhu berada di bawah 36.0 °C (hipotermia) atau di atas 37.5 °C (demam), orang tua perlu lebih memperhatikan kondisi anak. Demam ringan seringkali merupakan cara alami tubuh melawan virus, namun tetap memerlukan pemantauan ekstra dan asupan cairan yang cukup.',
                'image' => 'https://images.unsplash.com/photo-1543363136-31f0bb4d7dfb?auto=format&fit=crop&w=1200&q=80',
                'published_at' => now()->subDays(2),
            ],
            [
                'title' => 'Indeks Massa Tubuh (BMI) dan Pertumbuhan Ideal Anak',
                'excerpt' => 'Memahami BMI membantu orang tua menjaga berat badan anak tetap ideal.',
                'content' => 'Menghitung Body Mass Index (BMI) secara rutin dari rasio tinggi dan berat badan dapat menghindarkan anak dari risiko gizi buruk (kurus) maupun obesitas. Nilai BMI 18.5 hingga 24.9 sering dijadikan patokan berat badan normal. Pastikan anak mengonsumsi gizi seimbang untuk mendukung masa emas pertumbuhannya.',
                'image' => 'https://images.unsplash.com/photo-1503454537195-1dcabb73ffb9?auto=format&fit=crop&w=1200&q=80',
                'published_at' => now()->subDays(3),
            ],
            [
                'title' => 'Bahaya Obesitas pada Usia Dini',
                'excerpt' => 'Obesitas bukan sekadar kelebihan berat badan, melainkan pemicu risiko di masa depan.',
                'content' => 'Anak dengan BMI masuk kategori obesitas rentan mengalami gangguan pernapasan, mudah lelah, dan berisiko tinggi terkena penyakit metabolik kelak. Membatasi konsumsi makanan olahan dan jajanan tinggi kalori tak bergizi adalah langkah pertama yang krusial untuk mencegah obesitas sejak dini.',
                'image' => 'https://images.unsplash.com/photo-1476234251651-f353703a034d?auto=format&fit=crop&w=1200&q=80',
                'published_at' => now()->subDays(4),
            ],
            [
                'title' => 'Memilih Camilan (Snack) Sehat untuk Anak',
                'excerpt' => 'Camilan sehat memberikan energi stabil tanpa memicu lonjakan gula darah.',
                'content' => 'Alih-alih memberikan makanan ringan kemasan yang tinggi gula dan pengawet, pilihlah camilan sehat seperti potongan buah segar, yogurt tanpa pemanis, atau kacang-kacangan. Camilan sehat membantu anak tetap fokus saat belajar dan bermain tanpa membuat mereka merasa cepat lapar atau mengantuk.',
                'image' => 'https://images.unsplash.com/photo-1511895426328-dc8714191300?auto=format&fit=crop&w=1200&q=80',
                'published_at' => now()->subDays(5),
            ],
            [
                'title' => 'Aktivitas Fisik: Kunci Kebugaran Anak',
                'excerpt' => 'Mengajak anak aktif bergerak setidaknya 60 menit sehari untuk kesehatan jangka panjang.',
                'content' => 'Bermain di luar ruangan, bersepeda, atau berenang sangat dianjurkan untuk melatih kekuatan otot dan kardiovaskular anak. Aktivitas fisik yang rutin membantu menjaga kerja jantung tetap prima, membakar asupan kalori berlebih, dan membuat siklus tidur anak lebih teratur.',
                'image' => 'https://images.unsplash.com/photo-1509099836639-18ba1795216d?auto=format&fit=crop&w=1200&q=80',
                'published_at' => now()->subDays(6),
            ],
            [
                'title' => 'Mengelola Waktu Tidur untuk Tumbuh Kembang',
                'excerpt' => 'Tidur yang cukup sangat berpengaruh pada metabolisme dan hormon pertumbuhan.',
                'content' => 'Hormon pertumbuhan (Growth Hormone) bekerja paling optimal saat anak tertidur lelap di malam hari. Anak usia sekolah membutuhkan 9-11 jam tidur setiap harinya. Menariknya, kurang tidur seringkali terbukti memicu keinginan anak untuk mengonsumsi camilan manis berlebih pada keesokan harinya.',
                'image' => 'https://images.unsplash.com/photo-1579684288361-5c1a2951e0f0?auto=format&fit=crop&w=1200&q=80',
                'published_at' => now()->subDays(7),
            ],
            [
                'title' => 'Pentingnya Hidrasi: Cukupkah Anak Minum Air Putih?',
                'excerpt' => 'Dehidrasi ringan dapat menyebabkan anak kehilangan konsentrasi dan merasa lemas.',
                'content' => 'Anak-anak sering lupa minum karena terlalu asyik bermain. Pastikan mereka meminum setidaknya 6-8 gelas air putih sehari. Air mineral jauh lebih baik dibandingkan minuman bersoda atau teh manis kemasan karena bebas kalori ekstra dan sangat membantu fungsi ginjal.',
                'image' => 'https://images.unsplash.com/photo-1478147427282-58a87a120781?auto=format&fit=crop&w=1200&q=80',
                'published_at' => now()->subDays(8),
            ],
            [
                'title' => 'Mengenalkan Pola Makan "Isi Piringku"',
                'excerpt' => 'Porsi gizi seimbang sesuai dengan anjuran pakar kesehatan dan Kemenkes.',
                'content' => 'Konsep "Isi Piringku" mengajarkan proporsi makanan yang ideal: setengah piring diisi sayur dan buah-buahan, seperempat karbohidrat, dan seperempat lagi protein nabati maupun hewani. Porsi ini memastikan anak mendapat asupan makronutrien dan mikronutrien yang lengkap untuk tumbuh kembang.',
                'image' => 'https://images.unsplash.com/photo-1503454537195-1dcabb73ffb9?auto=format&fit=crop&w=1200&q=80',
                'published_at' => now()->subDays(9),
            ],
            [
                'title' => 'Peran Orang Tua dalam Edukasi Gizi Anak',
                'excerpt' => 'Kebiasaan sehat anak dibentuk dari apa yang mereka lihat dan pelajari di rumah.',
                'content' => 'Anak adalah peniru yang ulung. Jika orang tua terbiasa makan sayur dan mengontrol asupan camilan tidak sehat, anak secara otomatis akan mengikuti pola tersebut. Melibatkan anak dalam memilih makanan sehat dan mengedukasi mereka tentang pentingnya gizi akan meningkatkan kemandirian mereka dalam menjaga kesehatan.',
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
