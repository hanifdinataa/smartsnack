<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        $now = now();

        $products = [
            // [
            //     'barcode' => '8999918451368',
            //     'name' => 'Teh Botol Less Sugar',
            //     'category' => 'drink',
            //     'image' => 'https://github.com/jesicasp/product-images/blob/main/drink/1_Teh%20Botol%20Less%20Sugar.jpg?raw=true',
            //     'information' => 'Produk barcode demo untuk fitur scan.',
            //     'gr_sugar_content' => 12,
            //     'net_weight' => 250,
            //     'servings_per_package' => 1,
            //     'serving_size_ml' => 250,
            // ],
            // [
            //     'barcode' => '8999918451369',
            //     'name' => 'Golda Coffee Cappucino',
            //     'category' => 'drink',
            //     'image' => 'https://github.com/jesicasp/product-images/blob/main/drink/2_Golda%20Coffee%20Cappucino.jpg?raw=true',
            //     'information' => 'Produk barcode demo untuk fitur scan.',
            //     'gr_sugar_content' => 19,
            //     'net_weight' => 200,
            //     'servings_per_package' => 1,
            //     'serving_size_ml' => 200,
            // ],
            // [
            //     'barcode' => '8999918451370',
            //     'name' => 'YOU C1000 Orange',
            //     'category' => 'drink',
            //     'image' => 'https://github.com/jesicasp/product-images/blob/main/drink/3_YOUC1000%20Orange.jpg?raw=true',
            //     'information' => 'Produk barcode demo untuk fitur scan.',
            //     'gr_sugar_content' => 20,
            //     'net_weight' => 140,
            //     'servings_per_package' => 1,
            //     'serving_size_ml' => 140,
            // ],
            // [
            //     'barcode' => '8999918451371',
            //     'name' => 'Yupi Choco Glee',
            //     'category' => 'food',
            //     'image' => 'https://github.com/jesicasp/product-images/blob/main/food/38_Yupi%20Choco%20Glee.jpg?raw=true',
            //     'information' => 'Produk barcode demo untuk fitur scan.',
            //     'gr_sugar_content' => 3,
            //     'net_weight' => 6,
            //     'servings_per_package' => 7,
            //     'serving_size_ml' => 0,
            // ],
            // [
            //     'barcode' => '8999918451372',
            //     'name' => 'Nabati Wafer Richeese',
            //     'category' => 'food',
            //     'image' => 'https://github.com/jesicasp/product-images/blob/main/food/40_Nabati%20Wafer%20Richeese.jpg?raw=true',
            //     'information' => 'Produk barcode demo untuk fitur scan.',
            //     'gr_sugar_content' => 5,
            //     'net_weight' => 37,
            //     'servings_per_package' => 2.5,
            //     'serving_size_ml' => 0,
            // ],
        ];

        foreach ($products as $product) {
            $barcode = $product['barcode'];
            $exists = DB::table('products')->where('barcode', $barcode)->exists();

            if ($exists) {
                DB::table('products')
                    ->where('barcode', $barcode)
                    ->update([
                        'name' => $product['name'],
                        'category' => $product['category'],
                        'image' => $product['image'],
                        'information' => $product['information'],
                        'gr_sugar_content' => $product['gr_sugar_content'],
                        'net_weight' => $product['net_weight'],
                        'servings_per_package' => $product['servings_per_package'],
                        'serving_size_ml' => $product['serving_size_ml'],
                        'updated_at' => $now,
                    ]);
                continue;
            }

            DB::table('products')->insert([
                'name' => $product['name'],
                'barcode' => $product['barcode'],
                'category' => $product['category'],
                'image' => $product['image'],
                'information' => $product['information'],
                'gr_sugar_content' => $product['gr_sugar_content'],
                'net_weight' => $product['net_weight'],
                'servings_per_package' => $product['servings_per_package'],
                'serving_size_ml' => $product['serving_size_ml'],
                'created_at' => $now,
                'updated_at' => $now,
            ]);
        }
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        DB::table('products')
            ->whereIn('barcode', [
                '8999918451368',
                '8999918451369',
                '8999918451370',
                '8999918451371',
                '8999918451372',
            ])
            ->delete();
    }
};
