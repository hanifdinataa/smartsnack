<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class RecProductResource extends JsonResource
{
    /**
     * Transform the resource into an array.
     *
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $category = $this->category ?? null;
        $weight = $this->net_weight ?? null;

        if (!$weight) {
            $net_weight = null;
        } elseif ($category === 'drink') {
            $net_weight = (float)$weight . ' ml';
        } elseif ($category === 'food') {
            $net_weight = (float)$weight . ' gr';
        } else {
            $net_weight = $weight;
        }

        return [
            'product_id' => $this->id,
            'name' => $this->name,
            'image' => $this->image,
            'sugar_grade' => $this->sugar_grade,
            'gr_sugar_content' => (float) $this->gr_sugar_content,
            'net_weight' => $net_weight,
        ];
    }
}
