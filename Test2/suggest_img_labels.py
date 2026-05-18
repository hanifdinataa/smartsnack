"""
Suggest labels for IMG_*.jpg files by visual similarity.

Script ini tidak langsung mengubah dataset, karena label otomatis tetap perlu
dicek. Output-nya CSV berisi kandidat nama kemasan untuk gambar IMG_*.

Requirements:
  pip install tensorflow pillow pandas numpy
"""

from pathlib import Path

import numpy as np
import pandas as pd
import tensorflow as tf

IMAGE_SIZE = (224, 224)
PRODUCT_DIR = Path("product-images")
METADATA_CSV = Path("product_metadata.csv")
OUTPUT_CSV = Path("img_label_suggestions.csv")


def load_image(path: Path):
    raw = tf.io.read_file(str(path))
    img = tf.io.decode_image(raw, channels=3, expand_animations=False)
    img = tf.image.resize(img, IMAGE_SIZE)
    return tf.keras.applications.mobilenet_v2.preprocess_input(tf.cast(img, tf.float32))


def build_embedder():
    base = tf.keras.applications.MobileNetV2(
        input_shape=(*IMAGE_SIZE, 3),
        include_top=False,
        weights="imagenet",
        pooling="avg",
    )
    return base


def embed_paths(model, paths):
    vectors = []
    valid_paths = []
    skipped_paths = []
    for path in paths:
        try:
            img = load_image(path)
            vector = model(tf.expand_dims(img, axis=0), training=False).numpy()[0]
            norm = np.linalg.norm(vector)
            vectors.append(vector / norm if norm else vector)
            valid_paths.append(path)
        except Exception as exc:
            skipped_paths.append((path, str(exc).splitlines()[0]))
            print(f"[skip] Gambar tidak valid: {path.name}")
    return valid_paths, np.asarray(vectors, dtype=np.float32), skipped_paths


def main():
    if not METADATA_CSV.exists():
        raise FileNotFoundError("product_metadata.csv tidak ditemukan.")

    metadata = pd.read_csv(METADATA_CSV)
    known_rows = []
    for _, row in metadata.iterrows():
        category = str(row["category"]).strip().lower()
        filename = str(row["filename"]).strip()
        image_path = PRODUCT_DIR / category / filename
        if image_path.exists() and not filename.upper().startswith("IMG_"):
            known_rows.append({
                "name": str(row["name"]).strip(),
                "category": category,
                "filename": filename,
                "path": image_path,
            })

    unknown_paths = sorted(PRODUCT_DIR.glob("*/IMG_*.*"))
    if not known_rows:
        raise RuntimeError("Tidak ada gambar bernama produk sebagai pembanding.")
    if not unknown_paths:
        print("Tidak ada file IMG_* yang perlu ditebak.")
        return

    print(f"Known products : {len(known_rows)}")
    print(f"IMG candidates : {len(unknown_paths)}")
    print("Extracting visual embeddings...")

    model = build_embedder()
    known_paths, known_vectors, skipped_known = embed_paths(model, [row["path"] for row in known_rows])
    unknown_paths, unknown_vectors, skipped_unknown = embed_paths(model, unknown_paths)
    valid_known_rows = [
        row for row in known_rows if row["path"] in set(known_paths)
    ]

    if len(valid_known_rows) != len(known_rows):
        known_rows = valid_known_rows

    if len(skipped_known) + len(skipped_unknown) > 0:
        skipped_df = pd.DataFrame(
            [{"filename": path.name, "path": str(path), "error": error}
             for path, error in skipped_known + skipped_unknown]
        )
        skipped_df.to_csv("img_label_skipped_invalid.csv", index=False, encoding="utf-8")
        print("Invalid image report: img_label_skipped_invalid.csv")

    suggestions = []
    for img_path, vector in zip(unknown_paths, unknown_vectors):
        category = img_path.parent.name.lower()
        candidate_indexes = [
            idx for idx, row in enumerate(known_rows) if row["category"] == category
        ]
        if not candidate_indexes:
            candidate_indexes = list(range(len(known_rows)))

        scores = known_vectors[candidate_indexes] @ vector
        order = np.argsort(scores)[::-1][:3]
        ranked = [(candidate_indexes[i], float(scores[i])) for i in order]

        best_idx, best_score = ranked[0]
        suggestions.append({
            "filename": img_path.name,
            "category": category,
            "suggested_name": known_rows[best_idx]["name"],
            "confidence": round(best_score, 4),
            "top2_name": known_rows[ranked[1][0]]["name"] if len(ranked) > 1 else "",
            "top2_confidence": round(ranked[1][1], 4) if len(ranked) > 1 else "",
            "top3_name": known_rows[ranked[2][0]]["name"] if len(ranked) > 2 else "",
            "top3_confidence": round(ranked[2][1], 4) if len(ranked) > 2 else "",
        })

    pd.DataFrame(suggestions).to_csv(OUTPUT_CSV, index=False, encoding="utf-8")
    print(f"Saved: {OUTPUT_CSV}")
    print("Review confidence tinggi dulu sebelum dipakai untuk training.")


if __name__ == "__main__":
    main()
