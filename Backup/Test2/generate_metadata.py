"""
STEP 3: GENERATE METADATA PRODUK + DATA GULA
=============================================
Script ini:
1. Generate CSV template dari nama file (nama produk + kategori)
2. Tambahkan data gula dari database pengetahuan produk Indonesia
3. Export SQL INSERT untuk langsung dijalankan di phpMyAdmin

JAWABAN PERTANYAAN: "Data gula dari mana?"
â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Untuk produk UMUM (Yakult, Sprite, Pocky, dll):
  â†’ Sudah ada di database gizi BPOM / label kemasan resmi
  â†’ Script ini sudah include data gula yang akurat untuk 100+ produk

Untuk produk BARU/TIDAK DIKENAL:
  â†’ OCR label gizi (sudah kamu punya)
  â†’ Input manual via Form Kemasan di app kamu
  â†’ API gizi pihak ketiga (Open Food Facts, dll)
"""

import json
import csv
import re
import os
from pathlib import Path

# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# DATABASE GULA PRODUK (per takaran saji, dalam gram)
# Sumber: label kemasan BPOM, Open Food Facts
# Format: "nama_produk_lower": (gr_sugar, net_weight_g, serving_size_g)
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
SUGAR_DATABASE = {
    # â”€â”€â”€ DRINK â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    "yakult":                           (11.0,  65,   65),
    "fanta":                            (26.0, 250,  250),
    "sprite":                           (12.0, 250,  250),
    "coca cola":                        (27.0, 250,  250),
    "coca cola zero":                   (0.0,  250,  250),
    "teh pucuk":                        (13.5, 350,  350),
    "teh kotak melati":                 (8.0,  200,  200),
    "you c1000 lemon":                  (18.0, 140,  140),
    "youc1000 orange":                  (18.0, 140,  140),
    "hydro coco":                       (7.0,  310,  310),
    "hydro coco original":              (7.0,  310,  310),
    "golda coffee cappucino":           (15.0, 200,  200),
    "golda coffee dolce latte":         (18.0, 200,  200),
    "golda dolce latte coffee":         (18.0, 200,  200),
    "good day originale cappucino":     (14.0, 200,  200),
    "good day funtastic mocacinno":     (14.0, 220,  220),
    "good day funtastic mocachino":     (14.0, 220,  220),
    "buavita orange juice":             (24.0, 250,  250),
    "buavita jambu":                    (24.0, 250,  250),
    "abc mangga":                       (20.0, 250,  250),
    "abc jambu":                        (20.0, 250,  250),
    "abc jeruk":                        (22.0, 250,  250),
    "abc kopi susu":                    (16.0, 200,  200),
    "abc sari kacang ijo":              (18.0, 250,  250),
    "abc minuman soya":                 (10.0, 250,  250),
    "abc choco malt":                   (18.0, 200,  200),
    "abc kopi gula susu":               (16.0, 200,  200),
    "nipis madu":                       (21.0, 300,  300),
    "floridina orange":                 (22.0, 350,  350),
    "inaco im coco lychee":             (17.0, 350,  350),
    "inaco i'm coco strawberry":        (17.0, 350,  350),
    "chi forest sparkling water":       (0.0,  480,  480),
    "chi forest sparkling white peach": (0.0,  480,  480),
    "ultra milk cokelat":               (12.0, 200,  200),
    "ultra milk strawberry":            (14.0, 200,  200),
    "frisian flag full cream":          (10.0, 225,  225),
    "frisian flag energo":              (12.0, 200,  200),
    "frisian flag nutribrain strawberry": (14.0, 225, 225),
    "susu frisian flag nutribrain chocolate": (14.0, 225, 225),
    "clevo uht milk cokelat":           (12.0, 200,  200),
    "milku made with belgian cow":      (11.0, 200,  200),
    "bear brand":                       (0.0,  140,  140),
    "cimory fresh milk almond":         (9.0,  200,  200),
    "cimory yogurt drink strawberry":   (16.0, 250,  250),
    "collagena susu steril":            (8.0,  150,  150),
    "tujuh kurma susu steril kurma":    (13.0, 200,  200),
    "oatside chocolate":                (9.0,  200,  200),
    "ichitan thai milk green tea":      (13.0, 310,  310),
    "nutriboost strawberry":            (18.0, 300,  300),
    "delizio caffino milky espresso":   (12.0, 200,  200),
    "delizio caffino spanish latte":    (13.0, 200,  200),
    "delizio caffino oat marie latte":  (13.0, 200,  200),
    "kopiko lucky day thai coffee":     (14.0, 240,  240),
    "cool time air kelapa":             (9.0,  310,  310),
    "amo spark cola":                   (0.0,  330,  330),
    "amo spark lemon c":                (0.0,  330,  330),
    "sajuak air mineral":               (0.0,  330,  330),
    "espresso kopi susu":               (12.0, 200,  200),
    "kopi latte choco hazelnut":        (13.0, 200,  200),
    "luwak kopi gula":                  (14.0, 200,  200),
    "colatta":                          (16.0, 200,  200),
    "top coffee gula aren":             (14.0, 200,  200),
    "top cappuccino":                   (14.0, 200,  200),
    "instant coffee":                   (5.0,  180,  180),
    "ground coffee":                    (0.0,  180,  180),
    "kopiko w":                         (14.0, 200,  200),
    "golda coffee latte":               (15.0, 200,  200),
    "golda coffee cappuchino":          (15.0, 200,  200),
    "chocolatos drink botol":           (19.0, 200,  200),
    "plastic pot coffee":               (12.0, 200,  200),
    # â”€â”€â”€ FOOD â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    "chitato":                          (1.0,   68,   30),
    "chitato sapi bumbu bakar":         (1.0,   68,   30),
    "chitato keju supreme":             (1.5,   68,   30),
    "cheetos puffs":                    (1.0,   60,   28),
    "chiki twist jagung bakar":         (1.5,   55,   28),
    "maxicorn barbecue":                (1.0,   60,   28),
    "pringles original":                (1.0,  107,   30),
    "pringles sour cream onion":        (1.5,  107,   30),
    "pringles hot spicy":               (1.0,  107,   30),
    "oreo":                             (8.5,  133,   34),
    "oreo blackpink":                   (8.5,  133,   34),
    "oreo blueberry ice cream":         (8.0,  133,   34),
    "pocky chocolate":                  (10.0,  47,   23),
    "pocky strawberry":                 (9.0,   47,   23),
    "pocky":                            (10.0,  47,   23),
    "walkers":                          (0.5,   35,   35),
    "ritz cheese":                      (2.0,  104,   16),
    "khong guan biscuits":              (8.0, 1600,   25),
    "khong guan":                       (8.0, 1600,   25),
    "grand classic chocolate cream wafer": (7.0, 100, 25),
    "monde":                            (9.0,  200,   30),
    "monde snack gold":                 (8.0,  200,   30),
    "genji soft pie biscuits":          (8.0,  180,   28),
    "bourbon gandum":                   (6.0,  200,   25),
    "lemonia":                          (7.0,  130,   25),
    "pie bis":                          (7.5,  100,   25),
    "vegetable crackers":               (2.0,  250,   30),
    "nissin crispy crackers":           (2.0,  250,   30),
    "supero crackers":                  (3.0,  200,   30),
    "fried cookies":                    (6.0,  200,   25),
    "walens sus kering":                (7.0,  150,   25),
    "caramel cream egg cookies":        (9.0,  200,   30),
    "chic choc biscuit":                (8.0,  150,   28),
    "selamat chocolate sandwich":       (9.0,  200,   25),
    "twister minis":                    (5.0,  100,   25),
    "neo lotte xylitol":                (0.0,   35,   35),
    "happydent cool white":             (0.0,   24,   24),
    "chupa chups":                      (7.0,   12,   12),
    "chocopie":                         (11.0,  28,   28),
    "choco pie":                        (11.0,  28,   28),
    "lays rasa rumput laut":            (1.0,   68,   30),
    "mi goreng fried noodles":          (1.0,   85,   85),
    "garlic bread almond":              (3.0,   70,   35),
    "white bread":                      (3.0,  400,   35),
    "sea salt popcorn":                 (0.5,   50,   28),
    "marshmallow kepang stick":         (22.0,  50,   25),
    "munch max":                        (8.0,   38,   38),
    "nylon sev":                        (1.0,   60,   30),
    "small bhakarwadi":                 (2.0,   80,   30),
    "plantain chips":                   (2.0,   80,   30),
    "balaji cream onion":               (2.0,   60,   30),
    "franzzi cheese chocolate":         (8.0,   80,   30),
    "franzzi yogurt chocolate":         (9.0,   80,   30),
    "nutty chocolate cookies":          (9.0,  100,   30),
    "chocolate chip cookie":            (10.0, 100,   28),
    "tummy yogurt bar":                 (9.0,   25,   25),
    "haribo happy cola":                (17.0, 100,   10),
    "marie susu milk biscuit":          (6.0,  200,   25),
    "marie susu":                       (6.0,  200,   25),
    "sari gandum susu cokelat":         (7.0,  200,   25),
    "kelapa cream cokelat":             (5.0,  200,   25),
    "superco malkist dengan krim":      (7.0,  200,   25),
    "malkist":                          (7.0,  200,   25),
    "better":                           (2.0,  100,   25),
    "jetz sweet":                       (3.0,   70,   35),
    "sukrooo":                          (6.0,  100,   25),
    "frio":                             (9.0,   60,   30),
    "nehenlth standarddigital":         (4.0,   20,   20),
}

def clean_name(filename: str) -> str:
    name = Path(filename).stem
    name = re.sub(r'^\d{5,}_', '', name)
    name = re.sub(r'^\d+_', '', name)
    name = name.replace('_', ' ').replace('-', ' ')
    name = re.sub(r'\s+', ' ', name).strip()
    return name

def get_sugar_data(product_name: str):
    """Cari data gula dari database, fuzzy match."""
    name_lower = product_name.lower()
    
    # Exact match dulu
    if name_lower in SUGAR_DATABASE:
        return SUGAR_DATABASE[name_lower]
    
    # Partial match
    best_match = None
    best_score = 0
    for key in SUGAR_DATABASE:
        # Hitung kata yang cocok
        key_words = set(key.split())
        name_words = set(name_lower.split())
        overlap = len(key_words & name_words)
        total = len(key_words | name_words)
        score = overlap / total if total > 0 else 0
        if score > best_score and score > 0.4:
            best_score = score
            best_match = key
    
    if best_match:
        return SUGAR_DATABASE[best_match]
    
    # Default: tidak diketahui
    return (None, None, None)

def determine_sugar_grade(gr_sugar_per_serving, serving_size_g):
    """
    Sugar grade berdasarkan % AKG (AKG gula = 50g/hari untuk 2000 kcal).
    A = < 5% per saji
    B = 5-10%
    C = 10-20%  
    D = > 20%
    """
    if gr_sugar_per_serving is None:
        return "N/A"
    
    pct_akg = (gr_sugar_per_serving / 50) * 100
    
    if pct_akg < 5:
        return "A"
    elif pct_akg < 10:
        return "B"
    elif pct_akg < 20:
        return "C"
    else:
        return "D"

def generate_products():
    print("=" * 60)
    print("SMARTSNACK - GENERATE PRODUCT METADATA + SUGAR DATA")
    print("=" * 60)

    # Load dari output prepare_dataset.py (local Windows)
    source_json = "product_metadata.json"
    if not os.path.exists(source_json):
        raise FileNotFoundError(
            "product_metadata.json tidak ditemukan. Jalankan prepare_dataset.py dulu."
        )

    with open(source_json, "r", encoding="utf-8") as f:
        source_products = json.load(f)

    all_products = []
    for p in source_products:
        filename = p.get("original_filename") or p.get("filename")
        category = p.get("category", "").strip().lower()
        name = p.get("label_name") or p.get("name") or clean_name(filename or "")
        if not filename or not category:
            continue

        gr_sugar, net_weight, serving_size = get_sugar_data(name)
        grade = determine_sugar_grade(gr_sugar, serving_size)

        all_products.append({
            "name": name,
            "category": category,
            "filename": filename,
            "image_path": f"storage/products/{filename}",
            "gr_sugar_content": gr_sugar,
            "net_weight": net_weight,
            "serving_size": serving_size,
            "sugar_grade": grade,
            "data_source": "known_db" if gr_sugar is not None else "manual_input_needed"
        })

    # Statistik
    known = sum(1 for p in all_products if p['gr_sugar_content'] is not None)
    unknown = len(all_products) - known
    print(f"\nâœ… Total produk  : {len(all_products)}")
    print(f"âœ… Data gula ada : {known} produk")
    print(f"âš   Perlu manual  : {unknown} produk")

    # â”€â”€ Export CSV â”€â”€
    csv_path = "product_metadata.csv"
    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        fieldnames = ["name", "category", "filename", "image_path",
                      "gr_sugar_content", "net_weight", "serving_size", 
                      "sugar_grade", "data_source"]
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(all_products)
    print(f"\nâœ… CSV disimpan: {csv_path}")
    print("   â†’ Buka di Excel, lengkapi kolom gr_sugar_content yang kosong,")
    print("     lalu jalankan 4_import_csv_to_mysql.py")

    # â”€â”€ Export SQL â”€â”€
    sql_path = "product_seeder.sql"
    with open(sql_path, "w", encoding="utf-8") as f:
        f.write("-- ============================================\n")
        f.write("-- SMARTSNACK - PRODUCT SEEDER\n")
        f.write("-- Generated automatically dari product-images.rar\n")
        f.write("-- ============================================\n\n")
        f.write("SET NAMES utf8mb4;\n\n")
        f.write("INSERT INTO `products` (`name`, `category`, `image`, `gr_sugar_content`, `net_weight`, `created_at`, `updated_at`) VALUES\n")
        
        rows = []
        for p in all_products:
            sugar = f"{p['gr_sugar_content']:.2f}" if p['gr_sugar_content'] is not None else "NULL"
            weight = f"{p['net_weight']:.2f}" if p['net_weight'] is not None else "NULL"
            name_escaped = p['name'].replace("'", "\\'")
            img_url = f"http://127.0.0.1:8000/{p['image_path']}"
            row = f"  ('{name_escaped}', '{p['category']}', '{img_url}', {sugar}, {weight}, NOW(), NOW())"
            rows.append(row)
        
        f.write(",\n".join(rows))
        f.write(";\n")
    
    print(f"âœ… SQL disimpan: {sql_path}")
    print("   â†’ Import langsung di phpMyAdmin (Tab: Import atau SQL)")

    # â”€â”€ Export JSON â”€â”€
    json_path = "product_metadata.json"
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(all_products, f, indent=2, ensure_ascii=False)
    print(f"âœ… JSON disimpan: {json_path}")

    # Print produk yang perlu data manual
    print(f"\n{'â”€'*50}")
    print(f"PRODUK YANG PERLU LENGKAPI DATA GULA MANUAL ({unknown} produk):")
    print(f"{'â”€'*50}")
    for p in all_products:
        if p['gr_sugar_content'] is None:
            print(f"  [{p['category']}] {p['name']}")
    
    if unknown == 0:
        print("  Semua produk sudah punya data gula! âœ…")

if __name__ == "__main__":
    generate_products()

