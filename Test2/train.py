"""
STEP 2: TRAINING MODEL â†’ EXPORT .tflite
=========================================
MobileNetV2 Transfer Learning untuk klasifikasi kemasan produk.
Cocok untuk dataset kecil (sedikit gambar per kelas).

Requirements:
  pip install tensorflow pillow numpy

Jalankan setelah 1_prepare_dataset.py
"""

import os
import json
import csv
import numpy as np
import tensorflow as tf
from pathlib import Path

# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# KONFIGURASI â€” SESUAIKAN
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
DATASET_DIR   = "dataset"
LABELS_FILE   = "labels.txt"
IMAGE_SIZE    = (224, 224)
BATCH_SIZE    = 8          # Kecil karena dataset kecil
EPOCHS_FREEZE = int(os.getenv("EPOCHS_FREEZE", "3"))
EPOCHS_FINETUNE = int(os.getenv("EPOCHS_FINETUNE", "5"))
LEARNING_RATE = 0.001
FINETUNE_LR   = 0.0001
OUTPUT_MODEL  = "model/smartsnack_model.tflite"
OUTPUT_H5     = "model/smartsnack_model.h5"

# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# AUGMENTASI (penting untuk dataset kecil)
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
def load_product_metadata():
    metadata_path = Path("product_metadata.csv")
    metadata = {}
    if not metadata_path.exists():
        return metadata

    with metadata_path.open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            name = (row.get("name") or "").strip()
            if not name:
                continue
            metadata[name] = {
                "name": name,
                "category": (row.get("category") or "").strip().lower(),
                "filename": (row.get("filename") or "").strip(),
                "image_path": (row.get("image_path") or "").strip(),
                "gr_sugar_content": row.get("gr_sugar_content") or None,
                "net_weight": row.get("net_weight") or None,
            }
    return metadata

# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# LOAD DATASET
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
def load_datasets():
    train_root = Path(DATASET_DIR) / "train"
    val_root = Path(DATASET_DIR) / "val"
    class_names = sorted([p.name for p in train_root.iterdir() if p.is_dir()])
    num_classes = len(class_names)
    class_to_idx = {name: i for i, name in enumerate(class_names)}

    def collect_samples(root: Path):
        paths, labels = [], []
        for class_dir in root.iterdir():
            if not class_dir.is_dir() or class_dir.name not in class_to_idx:
                continue
            idx = class_to_idx[class_dir.name]
            for img_path in class_dir.glob("*"):
                if img_path.suffix.lower() in [".jpg", ".jpeg", ".png"]:
                    paths.append(str(img_path))
                    labels.append(idx)
        return paths, labels

    def decode_img(path, label):
        img = tf.io.read_file(path)
        img = tf.io.decode_image(img, channels=3, expand_animations=False)
        img = tf.image.resize(img, IMAGE_SIZE)
        img = tf.cast(img, tf.float32)
        label = tf.one_hot(label, depth=num_classes)
        return img, label

    train_paths, train_labels = collect_samples(train_root)
    val_paths, val_labels = collect_samples(val_root)

    train_ds = tf.data.Dataset.from_tensor_slices((train_paths, train_labels))
    train_ds = train_ds.shuffle(len(train_paths), seed=42).map(decode_img, num_parallel_calls=tf.data.AUTOTUNE).batch(BATCH_SIZE)
    val_ds = tf.data.Dataset.from_tensor_slices((val_paths, val_labels))
    val_ds = val_ds.map(decode_img, num_parallel_calls=tf.data.AUTOTUNE).batch(BATCH_SIZE)

    print(f"[Dataset] {num_classes} kelas ditemukan")
    print(f"[Dataset] Train images: {len(train_paths)}, Val images: {len(val_paths)}")
    
    if not train_paths or not val_paths:
        raise RuntimeError("Dataset kosong. Jalankan prepare_dataset.py dulu.")

    # Prefetch untuk performa
    AUTOTUNE = tf.data.AUTOTUNE
    train_ds = train_ds.prefetch(buffer_size=AUTOTUNE)
    val_ds = val_ds.prefetch(buffer_size=AUTOTUNE)
    
    return train_ds, val_ds, class_names, num_classes

# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# BUILD MODEL
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
def build_model(num_classes):
    if os.getenv("USE_MOBILENET", "0") == "1":
        preprocess_input = tf.keras.applications.mobilenet_v2.preprocess_input
        base_model = tf.keras.applications.MobileNetV2(
            input_shape=(*IMAGE_SIZE, 3),
            include_top=False,
            weights="imagenet",
        )
        base_model.trainable = False

        inputs = tf.keras.Input(shape=(*IMAGE_SIZE, 3))
        x = preprocess_input(inputs)
        x = base_model(x, training=False)
        x = tf.keras.layers.GlobalAveragePooling2D()(x)
        x = tf.keras.layers.Dropout(0.3)(x)
        x = tf.keras.layers.Dense(256, activation="relu")(x)
        x = tf.keras.layers.Dropout(0.3)(x)
        outputs = tf.keras.layers.Dense(num_classes, activation="softmax")(x)
        model = tf.keras.Model(inputs, outputs, name="smartsnack_classifier")
        return model, base_model

    # CNN ringan: lebih cepat dan stabil untuk export TFLite di Windows/Keras 3.
    inputs = tf.keras.Input(shape=(*IMAGE_SIZE, 3))
    x = tf.keras.layers.Rescaling(1.0 / 255.0)(inputs)
    x = tf.keras.layers.Conv2D(32, 3, activation="relu", padding="same")(x)
    x = tf.keras.layers.MaxPooling2D()(x)
    x = tf.keras.layers.Conv2D(64, 3, activation="relu", padding="same")(x)
    x = tf.keras.layers.MaxPooling2D()(x)
    x = tf.keras.layers.Conv2D(128, 3, activation="relu", padding="same")(x)
    x = tf.keras.layers.MaxPooling2D()(x)
    x = tf.keras.layers.GlobalAveragePooling2D()(x)
    x = tf.keras.layers.Dropout(0.3)(x)
    x = tf.keras.layers.Dense(256, activation="relu")(x)
    x = tf.keras.layers.Dropout(0.3)(x)
    outputs = tf.keras.layers.Dense(num_classes, activation="softmax")(x)
    model = tf.keras.Model(inputs, outputs, name="smartsnack_classifier")
    return model, None

# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# TRAINING
# â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
def train():
    print("=" * 60)
    print("SMARTSNACK - MODEL TRAINING")
    print("=" * 60)
    
    os.makedirs("model", exist_ok=True)
    
    # Load data
    train_ds, val_ds, class_names, num_classes = load_datasets()
    
    # Verifikasi urutan class_names sesuai labels.txt
    with open(LABELS_FILE, encoding="utf-8") as f:
        file_labels = [l.strip() for l in f if l.strip()]
    
    print(f"\n[Labels] File labels.txt: {len(file_labels)} kelas")
    print(f"[Labels] Dataset class_names: {len(class_names)} kelas")
    if len(file_labels) != len(class_names):
        print("[Labels] WARNING: jumlah labels.txt beda dengan folder dataset, pakai class_names dari dataset.")
    
    # Simpan class_names yang sebenarnya dipakai TF (urutan dari folder)
    with open("model/class_names.json", "w", encoding="utf-8") as f:
        json.dump(class_names, f, indent=2, ensure_ascii=False)
    print("[Labels] OK Disimpan ke model/class_names.json")

    metadata = load_product_metadata()
    model_metadata = []
    for idx, name in enumerate(class_names):
        item = metadata.get(name, {"name": name})
        item["label_index"] = idx
        model_metadata.append(item)
    with open("model/model_metadata.json", "w", encoding="utf-8") as f:
        json.dump(model_metadata, f, indent=2, ensure_ascii=False)
    print("[Labels] OK Disimpan ke model/model_metadata.json")

    # Build model
    print(f"\n[Model] Building classifier dengan {num_classes} output kelas...")
    model, base_model = build_model(num_classes)
    model.summary()

    # â”€â”€ FASE 1: Latih hanya head â”€â”€
    print(f"\n[Training] FASE 1: Melatih head ({EPOCHS_FREEZE} epoch)...")
    model.compile(
        optimizer=tf.keras.optimizers.Adam(LEARNING_RATE),
        loss="categorical_crossentropy",
        metrics=["accuracy"],
    )

    callbacks = [
        tf.keras.callbacks.ModelCheckpoint(
            "model/best_model.keras",
            monitor="val_accuracy",
            save_best_only=True,
            verbose=1,
        ),
        tf.keras.callbacks.EarlyStopping(
            monitor="val_accuracy",
            patience=5,
            restore_best_weights=True,
        ),
        tf.keras.callbacks.ReduceLROnPlateau(
            monitor="val_loss",
            factor=0.5,
            patience=3,
            verbose=1,
        ),
    ]

    history1 = model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=EPOCHS_FREEZE,
        callbacks=callbacks,
    )

    # â”€â”€ FASE 2: Fine-tuning â”€â”€
    if base_model is None or EPOCHS_FINETUNE <= 0:
        history2 = None
    else:
        print(f"\n[Training] FASE 2: Fine-tuning ({EPOCHS_FINETUNE} epoch)...")
    # Unfreeze 30 layer terakhir base_model
        base_model.trainable = True
        for layer in base_model.layers[:-30]:
            layer.trainable = False

        model.compile(
            optimizer=tf.keras.optimizers.Adam(FINETUNE_LR),
            loss="categorical_crossentropy",
            metrics=["accuracy"],
        )

        history2 = model.fit(
            train_ds,
            validation_data=val_ds,
            epochs=EPOCHS_FINETUNE,
            callbacks=callbacks,
        )

    # Simpan model H5
    model.save(OUTPUT_H5)
    print(f"\n[Saved] Model H5 â†’ {OUTPUT_H5}")

    # â”€â”€ EXPORT ke TFLite â”€â”€
    export_tflite(model, class_names)

def export_tflite(model, class_names):
    print("\n[TFLite] Mengonversi ke .tflite...")

    concrete_func = tf.function(lambda x: model(x, training=False)).get_concrete_function(
        tf.TensorSpec([1, *IMAGE_SIZE, 3], tf.float32)
    )
    from tensorflow.python.framework.convert_to_constants import convert_variables_to_constants_v2
    frozen_func = convert_variables_to_constants_v2(concrete_func)
    converter = tf.lite.TFLiteConverter.from_concrete_functions([frozen_func])

    tflite_model = converter.convert()
    
    os.makedirs(os.path.dirname(OUTPUT_MODEL), exist_ok=True)
    with open(OUTPUT_MODEL, "wb") as f:
        f.write(tflite_model)
    
    size_mb = os.path.getsize(OUTPUT_MODEL) / (1024 * 1024)
    print(f"[TFLite] OK Tersimpan: {OUTPUT_MODEL} ({size_mb:.1f} MB)")
    
    # Juga simpan labels.txt versi model (sesuai urutan TF)
    with open("model/labels.txt", "w", encoding="utf-8") as f:
        for name in class_names:
            f.write(name + "\n")
    print("[TFLite] OK labels.txt untuk model -> model/labels.txt")

    # Verifikasi TFLite
    print("\n[TFLite] Verifikasi model...")
    interpreter = tf.lite.Interpreter(model_path=OUTPUT_MODEL)
    interpreter.allocate_tensors()
    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()
    print(f"         Input shape : {input_details[0]['shape']}")
    print(f"         Output shape: {output_details[0]['shape']}")
    print("         Model valid dan siap dipakai di Flutter!")

    print("\n" + "=" * 60)
    print("TRAINING & EXPORT SELESAI!")
    print(f"   TFLite model : {OUTPUT_MODEL}")
    print(f"   Labels       : model/labels.txt")
    print(f"   Class names  : model/class_names.json")
    print("=" * 60)
    print("\nSelanjutnya copy file ini ke Flutter:")
    print("  assets/ml/my_model_quantized_uint8.tflite")
    print("  assets/ml/labels.txt")

if __name__ == "__main__":
    train()

