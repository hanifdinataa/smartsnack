"""
STEP 1: PREPARE DATASET
=======================
Script ini mengekstrak RAR, menyusun folder dataset untuk training,
dan men-generate label_map.json + labels.txt

Jalankan di komputer/server training (bukan mobile).
Requirements: pip install rarfile pillow
"""

import re
import json
import shutil
import rarfile
import csv
from pathlib import Path
from PIL import Image

# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# KONFIGURASI
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
RAR_PATH = "product-images.rar"          # Ganti path RAR kamu
OUTPUT_DIR = "dataset"                    # Folder output dataset
EXTRACT_DIR = "product-images-extracted"  # Folder hasil ekstrak manual/otomatis
IMAGE_SIZE = (224, 224)                   # Input size model (MobileNetV2)
METADATA_CSV = "product_metadata.csv"      # Sumber nama produk + kategori jika ada

def clean_product_name(filename: str) -> str:
    """Extract nama produk bersih dari nama file."""
    name = Path(filename).stem
    # Hapus barcode prefix (angka panjang di depan underscore)
    name = re.sub(r'^\d{5,}_', '', name)
    # Juga hapus format: angka_NamaProduk
    name = re.sub(r'^\d+_', '', name)
    # Ganti _ dan - dengan spasi
    name = name.replace('_', ' ').replace('-', ' ')
    # Hapus spasi berlebih
    name = re.sub(r'\s+', ' ', name).strip()
    # Title case
    return name

def load_metadata_products(source_base: Path):
    """Pakai metadata agar label model = nama kemasan, bukan nama file IMG_."""
    csv_path = Path(METADATA_CSV)
    if not csv_path.exists():
        return None

    products = []
    with csv_path.open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            category = (row.get("category") or "").strip().lower()
            filename = (row.get("filename") or "").strip()
            name = (row.get("name") or "").strip()
            if category not in {"food", "drink"} or not filename or not name:
                continue

            img_path = source_base / category / filename
            if not img_path.exists():
                print(f"      [skip] File gambar tidak ditemukan: {img_path}")
                continue

            products.append({
                "path": str(img_path),
                "name": name,
                "category": category,
                "filename": filename,
            })

    return products

def prepare_dataset():
    print("=" * 60)
    print("SMARTSNACK - DATASET PREPARATION")
    print("=" * 60)

    # Siapkan folder sumber gambar
    print(f"\n[1/5] Menyiapkan folder sumber gambar...")
    extract_dir = EXTRACT_DIR
    if Path(extract_dir).exists():
        print(f"      Folder ekstrak manual ditemukan -> {extract_dir}/")
        print("      Langsung lanjut tanpa ekstrak RAR")
    else:
        print(f"      Folder {extract_dir}/ belum ada, mencoba ekstrak {RAR_PATH}...")
        try:
            with rarfile.RarFile(RAR_PATH) as rf:
                rf.extractall(extract_dir)
            print(f"      Ekstraksi selesai -> {extract_dir}/")
        except FileNotFoundError:
            print("      File RAR tidak ditemukan, lanjut cek folder manual lain...")
        except rarfile.RarCannotExec:
            raise RuntimeError(
                f"Folder '{extract_dir}' tidak ditemukan dan tool ekstrak RAR tidak tersedia.\n"
                f"Silakan ekstrak manual '{RAR_PATH}' ke folder '{extract_dir}' lalu jalankan ulang script."
            )

    # Scan semua gambar
    print("\n[2/5] Scanning gambar...")
    all_images = []
    # Support 2 struktur:
    # 1) product-images-extracted/product-images/{food,drink}
    # 2) product-images/{food,drink}
    base_candidates = [
        Path(extract_dir) / "product-images",
        Path("product-images"),
    ]
    source_base = None
    for candidate in base_candidates:
        if (candidate / "food").exists() or (candidate / "drink").exists():
            source_base = candidate
            break
    if source_base is None:
        raise RuntimeError(
            "Folder gambar tidak ditemukan. Pastikan salah satu struktur ini ada:\n"
            "1) product-images-extracted/product-images/food|drink\n"
            "2) product-images/food|drink"
        )

    metadata_images = load_metadata_products(source_base)
    if metadata_images:
        all_images = metadata_images
        print(f"      Pakai metadata produk dari {METADATA_CSV}")
    else:
        for category in ["food", "drink"]:
            folder = source_base / category
            if not folder.exists():
                print(f"      Folder tidak ditemukan: {folder}")
                continue
            for pattern in ("*.jpg", "*.jpeg", "*.png"):
                for img_file in folder.glob(pattern):
                    product_name = clean_product_name(img_file.name)
                    all_images.append({
                        "path": str(img_file),
                        "name": product_name,
                        "category": category,
                        "filename": img_file.name
                    })

    print(f"      âœ“ Total gambar ditemukan: {len(all_images)}")
    food_count = sum(1 for x in all_images if x['category'] == 'food')
    drink_count = sum(1 for x in all_images if x['category'] == 'drink')
    print(f"      â€¢ Food : {food_count}")
    print(f"      â€¢ Drink: {drink_count}")

    # Build label mapping
    # Setiap produk unik = 1 class (berdasarkan nama file)
    print("\n[3/5] Membuat label mapping...")
    sorted_images = sorted(all_images, key=lambda x: (x['name'].lower(), x['filename'].lower()))
    
    labels = []
    label_to_index = {}
    label_map = {}
    product_metadata = []

    for img in sorted_images:
        key = img['name'].strip().lower()
        if key not in label_to_index:
            label_to_index[key] = len(labels)
            labels.append(img['name'])

    for img in sorted_images:
        stem = Path(img['filename']).stem
        idx = label_to_index[img['name'].strip().lower()]
        label_map[stem] = idx
        product_metadata.append({
            "label_index": idx,
            "label_name": img['name'],
            "category": img['category'],
            "original_filename": img['filename']
        })

    print(f"      âœ“ Total kelas (produk): {len(labels)}")

    # Buat struktur folder dataset
    print("\n[4/5] Menyusun folder dataset (train/val)...")
    dataset_path = Path(OUTPUT_DIR)
    if dataset_path.exists():
        shutil.rmtree(dataset_path)
    
    # Karena 1 gambar per produk, kita augment dulu
    # Untuk training real, kumpulkan lebih banyak gambar per produk
    # Saat ini: semua masuk train, copy juga ke val (workaround)
    for split in ["train", "val"]:
        for img in sorted_images:
            class_dir = dataset_path / split / img['name']
            class_dir.mkdir(parents=True, exist_ok=True)

    # Copy + resize gambar
    processed = 0
    for idx, img in enumerate(sorted_images):
        src = Path(img['path'])
        class_name = img['name']
        
        # Resize dan simpan ke train
        try:
            pil_img = Image.open(src).convert("RGB")
            pil_img_resized = pil_img.resize(IMAGE_SIZE, Image.LANCZOS)
            
            # Train
            safe_filename = f"{idx:04d}_{img['filename']}"
            dst_train = dataset_path / "train" / class_name / safe_filename
            pil_img_resized.save(str(dst_train))
            
            # Val (sama dulu karena 1 gambar per kelas)
            dst_val = dataset_path / "val" / class_name / safe_filename
            pil_img_resized.save(str(dst_val))
            
            processed += 1
        except Exception as e:
            print(f"      âš  Gagal proses {src.name}: {e}")

    print(f"      âœ“ Gambar diproses: {processed}")

    # Simpan labels.txt dan label_map.json
    print("\n[5/5] Menyimpan label files...")
    
    # labels.txt â€” satu nama per baris, index = urutan
    with open("labels.txt", "w", encoding="utf-8") as f:
        for label in labels:
            f.write(label + "\n")
    print("      âœ“ labels.txt")

    # label_map.json â€” filename_stem â†’ index
    with open("label_map.json", "w", encoding="utf-8") as f:
        json.dump(label_map, f, indent=2, ensure_ascii=False)
    print("      âœ“ label_map.json")

    # product_metadata.json â€” untuk import ke MySQL
    with open("product_metadata.json", "w", encoding="utf-8") as f:
        json.dump(product_metadata, f, indent=2, ensure_ascii=False)
    print("      âœ“ product_metadata.json")

    print("\n" + "=" * 60)
    print("âœ… DATASET SIAP!")
    print(f"   Folder    : {OUTPUT_DIR}/train/ dan {OUTPUT_DIR}/val/")
    print(f"   Labels    : labels.txt ({len(labels)} kelas)")
    print(f"   Label map : label_map.json")
    print(f"   Metadata  : product_metadata.json")
    print("=" * 60)
    print("\nâš   CATATAN PENTING:")
    print("   Dataset ini punya 1 gambar/kelas â†’ akurasi terbatas.")
    print("   Untuk production: kumpulkan 10-50 gambar per produk.")
    print("   Gunakan augmentasi di script training (sudah disertakan).")

if __name__ == "__main__":
    prepare_dataset()
