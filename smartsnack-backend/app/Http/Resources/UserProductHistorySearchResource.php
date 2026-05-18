<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class UserProductHistorySearchResource extends JsonResource
{
    /**
     * Transform the resource into an array.
     *
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $category = $this->product->category ?? null;
        $weight = $this->product->net_weight ?? null;

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
            'user_id' => $this->user_id,
            'product_id' => $this->product_id,
            'name' => $this->product->name,
            'image' => $this->product->image,
            'gr_sugar_content' => (float) $this->product->gr_sugar_content,
            'net_weight' => $net_weight,
            'sugar_grade' => $this->product->sugar_grade,
        ];
    }
}
