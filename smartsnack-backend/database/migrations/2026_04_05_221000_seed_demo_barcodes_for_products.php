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
        $barcodeMap = [
            'Teh Botol Less Sugar' => '8999918451368',
            'Golda Coffee Cappucino' => '8999918451369',
            'YOU C1000 Orange' => '8999918451370',
            'Yupi Choco Glee' => '8999918451371',
            'Nabati Wafer Richeese' => '8999918451372',
        ];

        foreach ($barcodeMap as $name => $barcode) {
            DB::table('products')
                ->where('name', $name)
                ->whereNull('barcode')
                ->update(['barcode' => $barcode]);
        }
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        $barcodes = [
            '8999918451368',
            '8999918451369',
            '8999918451370',
            '8999918451371',
            '8999918451372',
        ];

        DB::table('products')
            ->whereIn('barcode', $barcodes)
            ->update(['barcode' => null]);
    }
};
