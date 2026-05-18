<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class UserConsumptionResource extends JsonResource
{
    /**
     * Transform the resource into an array.
     *
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            //user consumption
            'id' => $this->id,
            'user_id' => $this->user_id,
            'product_id' => $this->product_id,
            'date' => $this->date,
            'sugar_grade' => $this->sugar_grade,
            'gr_sugar_consumed' => $this->gr_sugar_consumed,


            //product
            'product_name' => $this->product->name ?? null,
            'product_image' => $this->product->image ?? null,
            'amountConsumed' => $this->amountConsumed ?? null,
        ];
    }
}
