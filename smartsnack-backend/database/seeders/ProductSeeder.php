<?php

namespace Database\Seeders;

use Illuminate\Database\Console\Seeds\WithoutModelEvents;
use Illuminate\Database\Seeder;
use App\Models\Product;

class ProductSeeder extends Seeder
{
    /**
     * Run the database seeds.
     */
    public function run(): void
    {
        $products = [
            // [
            //     'name' => 'Teh Botol Less Sugar', 
            //     'barcode' => '8999918451368',
            //     'category' => 'drink', 
            //     'image' => 'https://github.com/jesicasp/product-images/blob/main/drink/1_Teh%20Botol%20Less%20Sugar.jpg?raw=true', 
            //     'information' => 'Minuman ini mengandung total gula sebanyak 23 gram per takaran saji 200 ml. Jika  kamu mengonsumsinya, pastikan asupan gula lainnya hari ini tidak lebih dari 27 gram untuk menjaga konsumsi gula tetap sesuai dengan rekomendasi harian.',
            //     'gr_sugar_content' => 12,
            //     'net_weight' => 250,
            //     'servings_per_package' => 1,
            //     'varian_ids' => [1], 
            // ],
            // [
            //     'name' => 'Golda Coffee Cappucino',
            //     'barcode' => '8999918451369',
            //     'category' => 'drink',
            //     'image' => 'https://github.com/jesicasp/product-images/blob/main/drink/2_Golda%20Coffee%20Cappucino.jpg?raw=true',
            //     'information' => 'Minuman ini mengandung total gula sebanyak 23 gram per takaran saji 200 ml. Jika  kamu mengonsumsinya, pastikan asupan gula lainnya hari ini tidak lebih dari 27 gram untuk menjaga konsumsi gula tetap sesuai dengan rekomendasi harian.',
            //     'gr_sugar_content' => 19,
            //     'net_weight' => 200,
            //     'servings_per_package' => 1,
            //     'varian_ids' => [2],
            // ],
            // [
            //     'name' => 'YOU C1000 Orange',
            //     'barcode' => '8999918451370',
            //     'category' => 'drink',
            //     'image' => 'https://github.com/jesicasp/product-images/blob/main/drink/3_YOUC1000%20Orange.jpg?raw=true',
            //     'information' => 'Minuman ini mengandung total gula sebanyak 23 gram per takaran saji 200 ml. Jika  kamu mengonsumsinya, pastikan asupan gula lainnya hari ini tidak lebih dari 27 gram untuk menjaga konsumsi gula tetap sesuai dengan rekomendasi harian.',
            //     'gr_sugar_content' => 20,
            //     'net_weight' => 140,
            //     'servings_per_package' => 1,
            //     'varian_ids' => [4],
            // ],
            // [
            //     'name' => 'Yupi Choco Glee',
            //     'barcode' => '8999918451371',
            //     'category' => 'food',
            //     'image' => 'https://github.com/jesicasp/product-images/blob/main/food/38_Yupi%20Choco%20Glee.jpg?raw=true',
            //     'information' => 'Makanan ini mengandung total gula sebanyak 23 gram per takaran saji 200 ml. Jika  kamu mengonsumsinya, pastikan asupan gula lainnya hari ini tidak lebih dari 27 gram untuk menjaga konsumsi gula tetap sesuai dengan rekomendasi harian.',
            //     'gr_sugar_content' => 3,
            //     'net_weight' => 6,
            //     'servings_per_package' => 7,
            //     'varian_ids' => [3],
            // ],
            // [
            //     'name' => 'Nabati Wafer Richeese',
            //     'barcode' => '8999918451372',
            //     'category' => 'food',
            //     'image' => 'https://github.com/jesicasp/product-images/blob/main/food/40_Nabati%20Wafer%20Richeese.jpg?raw=true',
            //     'information' => 'Makanan ini mengandung total gula sebanyak 23 gram per takaran saji 200 ml. Jika  kamu mengonsumsinya, pastikan asupan gula lainnya hari ini tidak lebih dari 27 gram untuk menjaga konsumsi gula tetap sesuai dengan rekomendasi harian.',
            //     'gr_sugar_content' => 5,
            //     'net_weight' => 37,
            //     'servings_per_package' => 2.5,
            //     'varian_ids' => [6,7],
            // ],
        ];

        foreach ($products as $data) {
            $product = Product::create([
                'name'             => $data['name'],
                'category'         => $data['category'],
                'image'            => $data['image'],
                'gr_sugar_content' => $data['gr_sugar_content'],
                'net_weight'       => $data['net_weight'],
            ]);

            echo "Created: {$product->name}\n";
        }
    }
}
