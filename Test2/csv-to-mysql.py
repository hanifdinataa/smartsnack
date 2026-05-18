"""
STEP 4: IMPORT CSV KE MYSQL
============================
Import product_metadata.csv ke tabel products dan salin foto produk ke
smartsnack-backend/storage/app/public/products.

Requirements:
  pip install pandas mysql-connector-python
"""

import shutil
from pathlib import Path

import pandas as pd

try:
    import mysql.connector
except ImportError:
    mysql = None

BACKEND_DIR = Path("..") / "smartsnack-backend"
ENV_FILE = BACKEND_DIR / ".env"
CSV_FILE = "product_metadata.csv"
SOURCE_IMAGE_DIR = Path("product-images")
PUBLIC_PRODUCT_DIR = BACKEND_DIR / "storage" / "app" / "public" / "products"
IMAGE_BASE_URL = "http://127.0.0.1:8000/storage/products/"


def read_env(path: Path):
    values = {}
    if not path.exists():
        return values
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


env = read_env(ENV_FILE)
DB_CONFIG = {
    "host": env.get("DB_HOST", "127.0.0.1"),
    "port": int(env.get("DB_PORT", "3306")),
    "database": env.get("DB_DATABASE", "db_smartsnack"),
    "user": env.get("DB_USERNAME", "root"),
    "password": env.get("DB_PASSWORD", ""),
}


def copy_product_image(category: str, filename: str) -> bool:
    src = SOURCE_IMAGE_DIR / category / filename
    if not src.exists():
        return False

    PUBLIC_PRODUCT_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, PUBLIC_PRODUCT_DIR / filename)
    return True


def to_float(value, default=0.0):
    if pd.isna(value) or str(value).strip() == "":
        return default
    return float(value)


def import_products():
    if mysql is None:
        print("[ERROR] Modul mysql-connector-python belum terpasang.")
        print("Jalankan: pip install mysql-connector-python")
        return

    print("=" * 60)
    print("SMARTSNACK - IMPORT CSV KE MYSQL")
    print("=" * 60)

    df = pd.read_csv(CSV_FILE)
    print(f"\n[CSV] {len(df)} produk dimuat dari {CSV_FILE}")

    required_cols = {"name", "category", "filename", "gr_sugar_content", "net_weight"}
    missing = required_cols - set(df.columns)
    if missing:
        print(f"[ERROR] Kolom tidak ditemukan: {missing}")
        return

    null_sugar = df["gr_sugar_content"].isna().sum()
    if null_sugar > 0:
        print(f"[INFO] {null_sugar} produk masih kosong gr_sugar_content, akan diset 0.0.")

    print("\n[MySQL] Connecting...")
    try:
        conn = mysql.connector.connect(**DB_CONFIG)
        cursor = conn.cursor()
        print("[MySQL] Connected")
    except Exception as e:
        compose_config = {
            "host": "127.0.0.1",
            "port": 3307,
            "database": "db_smartsnack",
            "user": "smartsnack",
            "password": "smartsnack",
        }
        print(f"[MySQL] Gagal dari .env: {e}")
        print("[MySQL] Mencoba koneksi Docker Compose di 127.0.0.1:3307...")
        try:
            conn = mysql.connector.connect(**compose_config)
            cursor = conn.cursor()
            print("[MySQL] Connected via Docker Compose")
        except Exception as fallback_error:
            print(f"[MySQL] Gagal: {fallback_error}")
            return

    inserted = 0
    updated = 0
    errors = 0
    copied_images = 0

    for _, row in df.iterrows():
        try:
            name = str(row["name"]).strip()
            category = str(row["category"]).strip().lower()
            filename = str(row["filename"]).strip()
            image_url = IMAGE_BASE_URL + filename
            gr_sugar = to_float(row["gr_sugar_content"])
            net_weight = to_float(row["net_weight"])

            if copy_product_image(category, filename):
                copied_images += 1

            cursor.execute("SELECT id FROM products WHERE name = %s", (name,))
            existing = cursor.fetchone()
            if existing:
                cursor.execute(
                    """
                    UPDATE products
                    SET category = %s,
                        image = %s,
                        gr_sugar_content = %s,
                        net_weight = %s,
                        updated_at = NOW()
                    WHERE id = %s
                    """,
                    (category, image_url, gr_sugar, net_weight, existing[0]),
                )
                updated += 1
                continue

            cursor.execute(
                """
                INSERT INTO products
                    (name, category, image, gr_sugar_content, net_weight, created_at, updated_at)
                VALUES
                    (%s, %s, %s, %s, %s, NOW(), NOW())
                """,
                (name, category, image_url, gr_sugar, net_weight),
            )
            inserted += 1

        except Exception as e:
            print(f"   Error pada '{row.get('name', '?')}': {e}")
            errors += 1

    conn.commit()
    cursor.close()
    conn.close()

    print("\n" + "=" * 60)
    print("IMPORT SELESAI")
    print(f"   Inserted : {inserted}")
    print(f"   Updated  : {updated}")
    print(f"   Images   : {copied_images} disalin ke storage/app/public/products")
    print(f"   Errors   : {errors}")
    print("=" * 60)


if __name__ == "__main__":
    import_products()
