<?php

namespace Database\Seeders;

use Illuminate\Database\Console\Seeds\WithoutModelEvents;
use Illuminate\Database\Seeder;
use App\Models\Varian;

class VarianSeeder extends Seeder
{
    /**
     * Run the database seeds.
     */
    public function run(): void
    {
        $varians = ['tea', 'coffee', 'jelly','orange','chocolate','wafer','cheese'];

        foreach ($varians as $name) {
            Varian::create(['name' => $name]);
        }

        echo "Varians seeded: tea, coffee, jelly\n";
    }
}
