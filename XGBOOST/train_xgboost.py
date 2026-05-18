
# ─────────────────────────────────────────────
# IMPORT LIBRARY
# ─────────────────────────────────────────────
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import matplotlib
matplotlib.use('Agg')  # non-interactive backend (aman untuk semua OS)

import warnings
warnings.filterwarnings('ignore')

from sklearn.model_selection    import train_test_split, GridSearchCV, StratifiedKFold
from sklearn.preprocessing      import LabelEncoder, StandardScaler
from sklearn.metrics            import (accuracy_score, precision_score,
                                        recall_score, f1_score,
                                        confusion_matrix, classification_report,
                                        roc_auc_score)
from sklearn.utils              import class_weight
from xgboost                    import XGBClassifier
import joblib
import os

# ─────────────────────────────────────────────
# KONFIGURASI
# ─────────────────────────────────────────────
DATASET_PATH     = "nhanes_complete_dataset.csv"
MODEL_PATH       = "model_xgboost.json"
SCALER_PATH      = "scaler.pkl"
ENCODER_PATH     = "label_encoder_gender.pkl"
EVALUASI_PATH    = "hasil_evaluasi.txt"
CM_PATH          = "confusion_matrix.png"
FI_PATH          = "feature_importance.png"

TEST_SIZE        = 0.2       # 80% train, 20% test
RANDOM_STATE     = 42

FITUR_KOLOM      = ['Age', 'Gender', 'Height', 'Weight', 'BMI', 'HeartRate', 'Temperature']
TARGET_KOLOM     = 'Diabetes'


# ══════════════════════════════════════════════
# STEP 1 — LOAD & VALIDASI DATASET
# ══════════════════════════════════════════════
print("=" * 60)
print("  SISTEM DETEKSI DINI RISIKO DIABETES — XGBoost")
print("  Tugas Akhir Hanif Dinata | Politeknik Negeri Padang")
print("=" * 60)

print("\n[STEP 1] Membaca dataset...")

if not os.path.isfile(DATASET_PATH):
    print(f"[ERROR] File '{DATASET_PATH}' tidak ditemukan.")
    print("Pastikan file ada di folder yang sama dengan script ini.")
    exit(1)

df = pd.read_csv(DATASET_PATH, sep=';', encoding='utf-8')

# Fallback jika file ternyata memakai koma, bukan titik koma
if len(df.columns) == 1 and ';' not in df.columns[0]:
    df = pd.read_csv(DATASET_PATH, sep=',', encoding='utf-8')
print(f"  Dataset dimuat     : {df.shape[0]} baris, {df.shape[1]} kolom")
print(f"  Kolom              : {list(df.columns)}")
print(f"\n  5 baris pertama:")
print(df.head().to_string(index=False))


# ══════════════════════════════════════════════
# STEP 2 — PRA-PEMROSESAN DATA
# ══════════════════════════════════════════════
print("\n[STEP 2] Pra-pemrosesan data...")

# 2a. Hapus baris yang label Diabetes-nya kosong (NaN)
before = len(df)
df = df[df[TARGET_KOLOM].notna()].copy()
after  = len(df)
print(f"  Baris dihapus (label kosong) : {before - after} baris")
print(f"  Baris tersisa                : {after} baris")

# 2b. Distribusi label
print(f"\n  Distribusi label '{TARGET_KOLOM}':")
dist = df[TARGET_KOLOM].value_counts()
for label, count in dist.items():
    pct = count / len(df) * 100
    print(f"    {label:<15}: {count} ({pct:.1f}%)")

# 2c. Encode Gender: Male → 0, Female → 1
le_gender = LabelEncoder()
df['Gender'] = le_gender.fit_transform(df['Gender'].astype(str))
print(f"\n  Encoding Gender    : {dict(zip(le_gender.classes_, le_gender.transform(le_gender.classes_)))}")

# 2d. Encode Diabetes: Diabetes → 1, No Diabetes → 0
df[TARGET_KOLOM] = df[TARGET_KOLOM].map({'Diabetes': 1, 'No Diabetes': 0})

# 2e. Tangani missing value — imputasi dengan median
print(f"\n  Missing value sebelum imputasi:")
for col in FITUR_KOLOM:
    n = df[col].isna().sum()
    if n > 0:
        median_val = df[col].median()
        df[col].fillna(median_val, inplace=True)
        print(f"    {col:<15}: {n} missing → diisi median ({median_val:.2f})")

print(f"  Missing value setelah imputasi: {df[FITUR_KOLOM].isna().sum().sum()} (semua bersih)")

# 2f. Pisahkan fitur dan target
X = df[FITUR_KOLOM].values
y = df[TARGET_KOLOM].values

print(f"\n  Fitur input (X)    : {X.shape}")
print(f"  Target output (y)  : {y.shape}")


# ══════════════════════════════════════════════
# STEP 3 — SPLIT DATA: TRAIN & TEST
# ══════════════════════════════════════════════
print(f"\n[STEP 3] Membagi data: {int((1-TEST_SIZE)*100)}% Train / {int(TEST_SIZE*100)}% Test...")

X_train, X_test, y_train, y_test = train_test_split(
    X, y,
    test_size    = TEST_SIZE,
    random_state = RANDOM_STATE,
    stratify     = y          # jaga proporsi kelas
)

print(f"  Data training      : {X_train.shape[0]} baris")
print(f"  Data testing       : {X_test.shape[0]} baris")


# ══════════════════════════════════════════════
# STEP 4 — NORMALISASI FITUR (StandardScaler)
# ══════════════════════════════════════════════
print("\n[STEP 4] Normalisasi fitur dengan StandardScaler...")

scaler  = StandardScaler()
X_train = scaler.fit_transform(X_train)
X_test  = scaler.transform(X_test)

print("  Normalisasi selesai: OK")


# ══════════════════════════════════════════════
# STEP 5 — HITUNG CLASS WEIGHT (untuk data imbalanced)
# ══════════════════════════════════════════════
print("\n[STEP 5] Menghitung class weight untuk menangani imbalanced data...")

classes       = np.unique(y_train)
weights       = class_weight.compute_class_weight('balanced', classes=classes, y=y_train)
scale_pos_w   = weights[1] / weights[0]   # bobot kelas positif (Diabetes)

print(f"  Class weight       : {dict(zip(classes, weights.round(2)))}")
print(f"  scale_pos_weight   : {scale_pos_w:.4f}")


# ══════════════════════════════════════════════
# STEP 6 — PELATIHAN MODEL XGBoost
# ══════════════════════════════════════════════
print("\n[STEP 6] Pelatihan model XGBoost...")
print("  Mencari hyperparameter terbaik dengan GridSearchCV...")
print("  (Proses ini memerlukan beberapa menit, harap tunggu...)\n")

# Parameter grid untuk tuning
param_grid = {
    'n_estimators'     : [100, 200, 300],
    'max_depth'        : [3, 5, 7],
    'learning_rate'    : [0.01, 0.05, 0.1],
    'subsample'        : [0.8, 1.0],
    'colsample_bytree' : [0.8, 1.0],
}

# Base model XGBoost
xgb_base = XGBClassifier(
    objective         = 'binary:logistic',
    eval_metric       = 'logloss',
    scale_pos_weight  = scale_pos_w,
    random_state      = RANDOM_STATE,
    use_label_encoder = False,
    verbosity         = 0,
)

# Cross-Validation dengan Stratified K-Fold (5 fold)
cv = StratifiedKFold(n_splits=5, shuffle=True, random_state=RANDOM_STATE)

grid_search = GridSearchCV(
    estimator  = xgb_base,
    param_grid = param_grid,
    cv         = cv,
    scoring    = 'f1',
    n_jobs     = -1,
    verbose    = 1,
)

grid_search.fit(X_train, y_train)

# Model terbaik
best_model  = grid_search.best_estimator_
best_params = grid_search.best_params_

print(f"\n  Hyperparameter terbaik:")
for k, v in best_params.items():
    print(f"    {k:<20}: {v}")
print(f"  Best CV F1-Score   : {grid_search.best_score_:.4f}")


# ══════════════════════════════════════════════
# STEP 7 — EVALUASI MODEL PADA DATA TEST
# ══════════════════════════════════════════════
print("\n[STEP 7] Evaluasi model pada data test...")

y_pred      = best_model.predict(X_test)
y_pred_prob = best_model.predict_proba(X_test)[:, 1]

acc       = accuracy_score(y_test, y_pred)
precision = precision_score(y_test, y_pred, zero_division=0)
recall    = recall_score(y_test, y_pred, zero_division=0)
f1        = f1_score(y_test, y_pred, zero_division=0)
auc       = roc_auc_score(y_test, y_pred_prob)
cm        = confusion_matrix(y_test, y_pred)

print(f"\n  ┌─────────────────────────────────┐")
print(f"  │        HASIL EVALUASI MODEL     │")
print(f"  ├─────────────────────────────────┤")
print(f"  │  Accuracy       : {acc:.4f}        │")
print(f"  │  Precision      : {precision:.4f}        │")
print(f"  │  Recall         : {recall:.4f}        │")
print(f"  │  F1-Score       : {f1:.4f}        │")
print(f"  │  AUC-ROC        : {auc:.4f}        │")
print(f"  └─────────────────────────────────┘")

print(f"\n  Confusion Matrix:")
print(f"    TN={cm[0,0]}  FP={cm[0,1]}")
print(f"    FN={cm[1,0]}  TP={cm[1,1]}")

print(f"\n  Classification Report:")
print(classification_report(y_test, y_pred,
      target_names=['No Diabetes', 'Diabetes']))


# ══════════════════════════════════════════════
# STEP 8 — SIMPAN MODEL & ARTEFAK
# ══════════════════════════════════════════════
print("[STEP 8] Menyimpan model dan artefak...")

best_model.save_model(MODEL_PATH)
joblib.dump(scaler,    SCALER_PATH)
joblib.dump(le_gender, ENCODER_PATH)

print(f"  Model disimpan     : {MODEL_PATH}")
print(f"  Scaler disimpan    : {SCALER_PATH}")
print(f"  Encoder disimpan   : {ENCODER_PATH}")


# ══════════════════════════════════════════════
# STEP 9 — SIMPAN LAPORAN EVALUASI (TXT)
# ══════════════════════════════════════════════
print(f"\n[STEP 9] Menyimpan laporan evaluasi ke '{EVALUASI_PATH}'...")

with open(EVALUASI_PATH, 'w') as f:
    f.write("=" * 60 + "\n")
    f.write("  LAPORAN EVALUASI MODEL XGBOOST\n")
    f.write("  Deteksi Dini Risiko Diabetes\n")
    f.write("  Tugas Akhir - Hanif Dinata (2301083015)\n")
    f.write("  Politeknik Negeri Padang\n")
    f.write("=" * 60 + "\n\n")
    f.write(f"Dataset       : {DATASET_PATH}\n")
    f.write(f"Total data    : {len(df)} baris\n")
    f.write(f"Split         : {int((1-TEST_SIZE)*100)}% Train / {int(TEST_SIZE*100)}% Test\n\n")
    f.write("HYPERPARAMETER TERBAIK (GridSearchCV):\n")
    for k, v in best_params.items():
        f.write(f"  {k:<25}: {v}\n")
    f.write(f"\nHASIL EVALUASI:\n")
    f.write(f"  Accuracy       : {acc:.4f}\n")
    f.write(f"  Precision      : {precision:.4f}\n")
    f.write(f"  Recall         : {recall:.4f}\n")
    f.write(f"  F1-Score       : {f1:.4f}\n")
    f.write(f"  AUC-ROC        : {auc:.4f}\n\n")
    f.write("CONFUSION MATRIX:\n")
    f.write(f"  TN={cm[0,0]}  FP={cm[0,1]}\n")
    f.write(f"  FN={cm[1,0]}  TP={cm[1,1]}\n\n")
    f.write("CLASSIFICATION REPORT:\n")
    f.write(classification_report(y_test, y_pred,
            target_names=['No Diabetes', 'Diabetes']))

print(f"  Laporan disimpan   : {EVALUASI_PATH}")


# ══════════════════════════════════════════════
# STEP 10 — VISUALISASI CONFUSION MATRIX
# ══════════════════════════════════════════════
print(f"\n[STEP 10] Membuat visualisasi Confusion Matrix...")

fig, ax = plt.subplots(figsize=(6, 5))
im = ax.imshow(cm, interpolation='nearest', cmap=plt.cm.Blues)
plt.colorbar(im, ax=ax)

classes_label = ['No Diabetes', 'Diabetes']
tick_marks    = np.arange(len(classes_label))
ax.set_xticks(tick_marks)
ax.set_yticks(tick_marks)
ax.set_xticklabels(classes_label, fontsize=12)
ax.set_yticklabels(classes_label, fontsize=12)

thresh = cm.max() / 2.0
for i in range(cm.shape[0]):
    for j in range(cm.shape[1]):
        ax.text(j, i, format(cm[i, j], 'd'),
                ha="center", va="center", fontsize=14,
                color="white" if cm[i, j] > thresh else "black")

ax.set_ylabel('Label Sebenarnya', fontsize=12)
ax.set_xlabel('Label Prediksi',   fontsize=12)
ax.set_title('Confusion Matrix — XGBoost\nDeteksi Dini Risiko Diabetes', fontsize=13, fontweight='bold')

plt.tight_layout()
plt.savefig(CM_PATH, dpi=150)
plt.close()
print(f"  Confusion Matrix disimpan  : {CM_PATH}")


# ══════════════════════════════════════════════
# STEP 11 — VISUALISASI FEATURE IMPORTANCE
# ══════════════════════════════════════════════
print(f"\n[STEP 11] Membuat visualisasi Feature Importance...")

importances = best_model.feature_importances_
indices     = np.argsort(importances)[::-1]
feat_names  = [FITUR_KOLOM[i] for i in indices]
feat_scores = importances[indices]

fig, ax = plt.subplots(figsize=(8, 5))
bars = ax.barh(feat_names[::-1], feat_scores[::-1],
               color='steelblue', edgecolor='white')

for bar, score in zip(bars, feat_scores[::-1]):
    ax.text(bar.get_width() + 0.002, bar.get_y() + bar.get_height() / 2,
            f'{score:.4f}', va='center', fontsize=10)

ax.set_xlabel('Importance Score', fontsize=12)
ax.set_title('Feature Importance — XGBoost\nDeteksi Dini Risiko Diabetes', fontsize=13, fontweight='bold')
ax.set_xlim(0, max(feat_scores) + 0.05)
plt.tight_layout()
plt.savefig(FI_PATH, dpi=150)
plt.close()
print(f"  Feature Importance disimpan: {FI_PATH}")


# ══════════════════════════════════════════════
# STEP 12 — FUNGSI PREDIKSI UNTUK SISTEM IoT
# ══════════════════════════════════════════════
print("\n[STEP 12] Demonstrasi fungsi prediksi (simulasi data dari ESP32)...")

def prediksi_risiko_diabetes(age, gender, height, weight, bmi, heart_rate, temperature_celsius):
    """
    Fungsi prediksi risiko diabetes berdasarkan parameter non-invasive.

    Parameter:
      age               : Usia (tahun)
      gender            : 'Male' atau 'Female'
      height            : Tinggi badan (cm)
      weight            : Berat badan (kg)
      bmi               : Body Mass Index
      heart_rate        : Detak jantung (bpm) — dari sensor MAX30102
      temperature_celsius: Suhu tubuh (°C) — dari sensor MLX90614

    Return:
      dict berisi label risiko, probabilitas, dan rekomendasi
    """
    # Load artefak (model, scaler, encoder)
    model   = XGBClassifier()
    model.load_model(MODEL_PATH)
    sc      = joblib.load(SCALER_PATH)
    le      = joblib.load(ENCODER_PATH)

    # Encode gender
    gender_enc = le.transform([gender])[0]

    # Susun input fitur
    input_data = np.array([[age, gender_enc, height, weight, bmi, heart_rate, temperature_celsius]])

    # Normalisasi
    input_scaled = sc.transform(input_data)

    # Prediksi
    label_enc = model.predict(input_scaled)[0]
    prob      = model.predict_proba(input_scaled)[0]

    label     = 'Diabetes' if label_enc == 1 else 'No Diabetes'
    prob_dm   = round(float(prob[1]) * 100, 2)
    prob_no   = round(float(prob[0]) * 100, 2)

    # Rekomendasi berdasarkan hasil
    if label == 'Diabetes':
        rekomendasi = "RISIKO TINGGI: Disarankan konsultasi ke dokter dan batasi konsumsi gula."
        aksi_snack  = "DITOLAK — Smart Snack Box TERKUNCI"
    else:
        rekomendasi = "RISIKO RENDAH: Tetap jaga pola makan dan aktivitas fisik yang sehat."
        aksi_snack  = "DIIZINKAN — Smart Snack Box TERBUKA"

    return {
        'label'         : label,
        'probabilitas'  : {'Diabetes': f'{prob_dm}%', 'No Diabetes': f'{prob_no}%'},
        'rekomendasi'   : rekomendasi,
        'aksi_snack_box': aksi_snack,
    }


# ── Contoh prediksi ──
contoh_input = {
    'age'                  : 13,
    'gender'               : 'Male',
    'height'               : 155.0,
    'weight'               : 60.0,
    'bmi'                  : 24.97,
    'heart_rate'           : 88,
    'temperature_celsius'  : 37.2,
}

print(f"\n  Input data (simulasi sensor ESP32):")
for k, v in contoh_input.items():
    print(f"    {k:<25}: {v}")

hasil = prediksi_risiko_diabetes(**contoh_input)

print(f"\n  Hasil Prediksi:")
print(f"    Label Risiko     : {hasil['label']}")
print(f"    Probabilitas     : {hasil['probabilitas']}")
print(f"    Rekomendasi      : {hasil['rekomendasi']}")
print(f"    Aksi Snack Box   : {hasil['aksi_snack_box']}")


# ══════════════════════════════════════════════
# RINGKASAN AKHIR
# ══════════════════════════════════════════════
print("\n" + "=" * 60)
print("  RINGKASAN FILE OUTPUT")
print("=" * 60)
output_files = [MODEL_PATH, SCALER_PATH, ENCODER_PATH,
                EVALUASI_PATH, CM_PATH, FI_PATH]
for f in output_files:
    size = os.path.getsize(f) if os.path.isfile(f) else 0
    print(f"  {f:<35} ({size:,} bytes)")

print()
print(f"  Accuracy  : {acc:.4f}  ({acc*100:.2f}%)")
print(f"  Precision : {precision:.4f}  ({precision*100:.2f}%)")
print(f"  Recall    : {recall:.4f}  ({recall*100:.2f}%)")
print(f"  F1-Score  : {f1:.4f}  ({f1*100:.2f}%)")
print(f"  AUC-ROC   : {auc:.4f}  ({auc*100:.2f}%)")
print()
print("=" * 60)
print("  SELESAI — Model XGBoost berhasil dilatih!")
print("=" * 60)
