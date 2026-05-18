<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class StoreSuggestedProductRequest extends FormRequest
{
    /**
     * Determine if the user is authorized to make this request.
     */
    public function authorize(): bool
    {
        return true;
    }

    /**
     * Get the validation rules that apply to the request.
     *
     * @return array<string, \Illuminate\Contracts\Validation\ValidationRule|array<mixed>|string>
     */
    public function rules(): array
    {
        return [
            'name' => 'required|string|max:255',
            'category' => 'required|in:food,drink',
            'image' => 'nullable|image|mimes:jpeg,png,jpg|max:2048',
            'gr_sugar_content' => 'required|numeric',
            'net_weight' => 'required|numeric',
            'servings_per_package' => 'required|numeric',
            'serving_size_ml' => 'required|numeric',
        ];
    }
}
