# ─────────────────────────────────────────────
# IMPORT LIBRARY
# ─────────────────────────────────────────────
# Import pandas (disingkat pd) untuk membaca dan mengolah data tabular (CSV/dataframe)
import pandas as pd
# Import numpy (disingkat np) untuk komputasi numerik dan operasi matriks
import numpy as np
# Import matplotlib.pyplot (disingkat plt) untuk membuat grafik/visualisasi
import matplotlib.pyplot as plt
import matplotlib
# Mengatur backend Matplotlib agar berjalan di mode headless (tanpa window GUI, cocok untuk server/terminal)
matplotlib.use('Agg')

# Import modul warnings untuk menyembunyikan pesan peringatan yang tidak kritis saat eksekusi
import warnings
warnings.filterwarnings('ignore')

# Import modul dari scikit-learn untuk membagi dataset, tuning hyperparameter, dan evaluasi K-Fold
from sklearn.model_selection import train_test_split, GridSearchCV, StratifiedKFold
# Import modul scikit-learn untuk encoding teks ke angka dan standarisasi fitur numerik
from sklearn.preprocessing import LabelEncoder, StandardScaler
# Import modul scikit-learn untuk menghitung metrik performa model ML
from sklearn.metrics import (accuracy_score, precision_score,
                            recall_score, f1_score,
                            confusion_matrix, classification_report,
                            roc_auc_score)
# Import modul penyeimbang bobot kelas untuk menangani dataset imbalanced
from sklearn.utils import class_weight
# Import algoritma utama XGBoost Classifier
from xgboost import XGBClassifier
# Import joblib untuk menyimpan dan memuat file artefak (.pkl)
import joblib
# Import os untuk periksa sistem berkas (misal ketersediaan file)
import os

# ─────────────────────────────────────────────
# KONFIGURASI NAMA FILE & PARAMETER TRAIN
# ─────────────────────────────────────────────
# Path file dataset masukan (NHANES dataset)
DATASET_PATH     = "nhanes_complete_dataset.csv"
# Path file output hasil simpanan model XGBoost
MODEL_PATH       = "model_xgboost.json"
# Path file output hasil simpanan scaler (StandardScaler)
SCALER_PATH      = "scaler.pkl"
# Path file output hasil simpanan encoder label gender
ENCODER_PATH     = "label_encoder_gender.pkl"
# Path file laporan teks hasil evaluasi model
EVALUASI_PATH    = "hasil_evaluasi.txt"
# Path gambar grafik Confusion Matrix
CM_PATH          = "confusion_matrix.png"
# Path gambar grafik Feature Importance (tingkat kepentingan fitur)
FI_PATH          = "feature_importance.png"

# Proporsi pembagian data uji (20% test data, 80% training data)
TEST_SIZE        = 0.2
# Seed random state agar hasil pembagian data dan training selalu konsisten setiap di-run
RANDOM_STATE     = 42

# Daftar nama 7 kolom fitur input yang digunakan oleh model
FITUR_KOLOM      = ['Age', 'Gender', 'Height', 'Weight', 'BMI', 'HeartRate', 'Temperature']
# Nama kolom target/output yang ingin diprediksi (0 = No Diabetes, 1 = Diabetes)
TARGET_KOLOM     = 'Diabetes'


# ══════════════════════════════════════════════
# STEP 1 — LOAD & VALIDASI DATASET
# ══════════════════════════════════════════════
print("=" * 60)
print("  -")
print("  -")
print("=" * 60)

print("\n[STEP 1] Membaca dataset...")

# Periksa apakah file dataset CSV benar-benar ada di folder
if not os.path.isfile(DATASET_PATH):
    print(f"[ERROR] File '{DATASET_PATH}' tidak ditemukan.")
    print("Pastikan file ada di folder yang sama dengan script ini.")
    exit(1)

# Membaca dataset CSV dengan pemisah titik koma (;)
df = pd.read_csv(DATASET_PATH, sep=';', encoding='utf-8')

# Fallback otomatis: jika pemisah CSV ternyata koma (,), baca ulang dengan sep=','
if len(df.columns) == 1 and ';' not in df.columns[0]:
    df = pd.read_csv(DATASET_PATH, sep=',', encoding='utf-8')

# Tampilkan jumlah baris dan kolom yang berhasil dibaca
print(f"  Dataset dimuat     : {df.shape[0]} baris, {df.shape[1]} kolom")
print(f"  Kolom              : {list(df.columns)}")
print(f"\n  5 baris pertama:")
# Tampilkan 5 baris pertama dataset tanpa indeks
print(df.head().to_string(index=False))


# ══════════════════════════════════════════════
# STEP 2 — PRA-PEMROSESAN DATA (DATA PREPROCESSING)
# ══════════════════════════════════════════════
print("\n[STEP 2] Pra-pemrosesan data...")

# 2a. Hapus baris data yang label Diabetes-nya kosong (NaN/null)
before = len(df)
df = df[df[TARGET_KOLOM].notna()].copy()
after  = len(df)
print(f"  Baris dihapus (label kosong) : {before - after} baris")
print(f"  Baris tersisa                : {after} baris")

# 2b. Hitung dan tampilkan distribusi jumlah sampel untuk kelas Diabetes vs No Diabetes
print(f"\n  Distribusi label '{TARGET_KOLOM}':")
dist = df[TARGET_KOLOM].value_counts()
for label, count in dist.items():
    pct = count / len(df) * 100
    print(f"    {label:<15}: {count} ({pct:.1f}%)")

# 2c. Enkode teks Gender ('Male'/'Female') menjadi angka menggunakan LabelEncoder
le_gender = LabelEncoder()
df['Gender'] = le_gender.fit_transform(df['Gender'].astype(str))
# Tampilkan pemetaan angka hasil enkode gender (misal Male=1, Female=0)
print(f"\n  Encoding Gender    : {dict(zip(le_gender.classes_, le_gender.transform(le_gender.classes_)))}")

# 2d. Enkode label target: 'Diabetes' diubah jadi 1, 'No Diabetes' diubah jadi 0
df[TARGET_KOLOM] = df[TARGET_KOLOM].map({'Diabetes': 1, 'No Diabetes': 0})

# 2e. Tangani missing value (data kosong) pada kolom fitur menggunakan Imputasi Median
print(f"\n  Missing value sebelum imputasi:")
for col in FITUR_KOLOM:
    n = df[col].isna().sum()
    if n > 0:
        # Hitung nilai tengah (median) dari kolom tersebut
        median_val = df[col].median()
        # Isi data kosong dengan nilai median
        df[col].fillna(median_val, inplace=True)
        print(f"    {col:<15}: {n} missing → diisi median ({median_val:.2f})")

print(f"  Missing value setelah imputasi: {df[FITUR_KOLOM].isna().sum().sum()} (semua bersih)")

# 2f. Memisahkan array matriks fitur (X) dan vektor label target (y)
X = df[FITUR_KOLOM].values
y = df[TARGET_KOLOM].values

print(f"\n  Fitur input (X)    : {X.shape}")
print(f"  Target output (y)  : {y.shape}")


# ══════════════════════════════════════════════
# STEP 3 — SPLIT DATA: TRAIN & TEST
# ══════════════════════════════════════════════
# Membagi dataset menjadi 80% data latih (train) dan 20% data uji (test)
print(f"\n[STEP 3] Membagi data: {int((1-TEST_SIZE)*100)}% Train / {int(TEST_SIZE*100)}% Test...")

X_train, X_test, y_train, y_test = train_test_split(
    X, y,
    test_size    = TEST_SIZE,
    random_state = RANDOM_STATE,
    stratify     = y          # stratify=y memastikan rasio kelas 0 & 1 tetap seimbang di train dan test
)

print(f"  Data training      : {X_train.shape[0]} baris")
print(f"  Data testing       : {X_test.shape[0]} baris")


# ══════════════════════════════════════════════
# STEP 4 — NORMALISASI FITUR (StandardScaler)
# ══════════════════════════════════════════════
print("\n[STEP 4] Normalisasi fitur dengan StandardScaler...")

# Inisialisasi StandardScaler (mengubah distribusi data sehingga mean=0 dan std=1)
scaler  = StandardScaler()
# Fit & transform pada data training (menghitung rata-rata & deviasi standar data latih)
X_train = scaler.fit_transform(X_train)
# Transform pada data testing menggunakan parameter skala yang sudah dipelajari dari data latih
X_test  = scaler.transform(X_test)

print("  Normalisasi selesai: OK")


# ══════════════════════════════════════════════
# STEP 5 — HITUNG CLASS WEIGHT (UNTUK IMBALANCED DATA)
# ══════════════════════════════════════════════
print("\n[STEP 5] Menghitung class weight untuk menangani imbalanced data...")

# Mengambil daftar kelas unik (0 dan 1)
classes       = np.unique(y_train)
# Menghitung bobot seimbang secara otomatis berdasarkan frekuensi munculnya tiap kelas
weights       = class_weight.compute_class_weight('balanced', classes=classes, y=y_train)
# Rasio bobot kelas positif (Diabetes / 1) terhadap kelas negatif (No Diabetes / 0) untuk parameter XGBoost
scale_pos_w   = weights[1] / weights[0]

print(f"  Class weight       : {dict(zip(classes, weights.round(2)))}")
print(f"  scale_pos_weight   : {scale_pos_w:.4f}")


# ══════════════════════════════════════════════
# STEP 6 — PELATIHAN MODEL XGBOOST & TUNING HYPERPARAMETER
# ══════════════════════════════════════════════
print("\n[STEP 6] Pelatihan model XGBoost...")
print("  Mencari hyperparameter terbaik dengan GridSearchCV...")
print("  (Proses ini memerlukan beberapa menit, harap tunggu...)\n")

# Ruang pencarian kombinasi hyperparameter terbaik (Hyperparameter Grid)
param_grid = {
    'n_estimators'     : [100, 200, 300],  # Jumlah pohon keputusan (decision trees)
    'max_depth'        : [3, 5, 7],       # Kedalaman maksimal tiap pohon
    'learning_rate'    : [0.01, 0.05, 0.1],# Laju pembagian bobot pemelajaran
    'subsample'        : [0.8, 1.0],      # Rasio data sampel yang digunakan per pohon
    'colsample_bytree' : [0.8, 1.0],      # Rasio kolom fitur yang digunakan per pohon
}

# Base model XGBoost Classifier dengan konfigurasi awal
xgb_base = XGBClassifier(
    objective         = 'binary:logistic', # Fungsi tujuan klasifikasi biner
    eval_metric       = 'logloss',         # Metrik evaluasi logaritma loss
    scale_pos_weight  = scale_pos_w,       # Penyeimbang bobot kelas positif
    random_state      = RANDOM_STATE,      # Reproduosibilitas hasil
    use_label_encoder = False,
    verbosity         = 0,
)

# Cross-Validation 5-Fold dengan Stratified K-Fold
cv = StratifiedKFold(n_splits=5, shuffle=True, random_state=RANDOM_STATE)

# Inisialisasi GridSearchCV untuk menguji semua kombinasi hyperparameter secara otomatis
grid_search = GridSearchCV(
    estimator  = xgb_base,
    param_grid = param_grid,
    cv         = cv,
    scoring    = 'f1',        # Mengoptimalkan skor F1-Score
    n_jobs     = -1,          # Gunakan semua core CPU untuk mempercepat proses
    verbose    = 1,
)

# Jalankan proses pelatihan dan tuning pada data latih
grid_search.fit(X_train, y_train)

# Ambil model terbaik hasil tuning beserta hyperparameter terbaiknya
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

# Prediksi label kelas pada data uji (X_test)
y_pred      = best_model.predict(X_test)
# Prediksi nilai probabilitas kelas positif (Diabetes)
y_pred_prob = best_model.predict_proba(X_test)[:, 1]

# Hitung metrik evaluasi klasifikasi
acc       = accuracy_score(y_test, y_pred)
precision = precision_score(y_test, y_pred, zero_division=0)
recall    = recall_score(y_test, y_pred, zero_division=0)
f1        = f1_score(y_test, y_pred, zero_division=0)
auc       = roc_auc_score(y_test, y_pred_prob)
cm        = confusion_matrix(y_test, y_pred)

# Tampilkan ringkasan metrik di konsol
print(f"\n  ┌─────────────────────────────────┐")
print(f"  │        HASIL EVALUASI MODEL     │")
print(f"  ├─────────────────────────────────┤")
print(f"  │  Accuracy       : {acc:.4f}        │")
print(f"  │  Precision      : {precision:.4f}        │")
print(f"  │  Recall         : {recall:.4f}        │")
print(f"  │  F1-Score       : {f1:.4f}        │")
print(f"  │  AUC-ROC        : {auc:.4f}        │")
print(f"  └─────────────────────────────────┘")

# Tampilkan rincian Confusion Matrix (True Negative, False Positive, False Negative, True Positive)
print(f"\n  Confusion Matrix:")
print(f"    TN={cm[0,0]}  FP={cm[0,1]}")
print(f"    FN={cm[1,0]}  TP={cm[1,1]}")

print(f"\n  Classification Report:")
print(classification_report(y_test, y_pred,
      target_names=['No Diabetes', 'Diabetes']))


# ══════════════════════════════════════════════
# STEP 8 — SIMPAN MODEL & ARTEFAK HASIL TRAINING
# ══════════════════════════════════════════════
print("[STEP 8] Menyimpan model dan artefak...")

# Simpan struktur & bobot model XGBoost ke file JSON
best_model.save_model(MODEL_PATH)
# Simpan objek scaler ke file .pkl
joblib.dump(scaler,    SCALER_PATH)
# Simpan objek encoder gender ke file .pkl
joblib.dump(le_gender, ENCODER_PATH)

print(f"  Model disimpan     : {MODEL_PATH}")
print(f"  Scaler disimpan    : {SCALER_PATH}")
print(f"  Encoder disimpan   : {ENCODER_PATH}")


# ══════════════════════════════════════════════
# STEP 9 — SIMPAN LAPORAN EVALUASI KE FILE TEKS (.TXT)
# ══════════════════════════════════════════════
print(f"\n[STEP 9] Menyimpan laporan evaluasi ke '{EVALUASI_PATH}'...")

# Tulis seluruh metrik evaluasi dan hyperparameter ke file teks hasil_evaluasi.txt
with open(EVALUASI_PATH, 'w') as f:
    f.write("=" * 60 + "\n")
    f.write("  LAPORAN EVALUASI MODEL XGBOOST\n")
    f.write("  \n")
    f.write("  \n")
    f.write("  \n")
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
# STEP 10 — VISUALISASI GRAFIK CONFUSION MATRIX (PNG)
# ══════════════════════════════════════════════
print(f"\n[STEP 10] Membuat visualisasi Confusion Matrix...")

# Buat canvas gambar matplotlib
fig, ax = plt.subplots(figsize=(6, 5))
im = ax.imshow(cm, interpolation='nearest', cmap=plt.cm.Blues)
plt.colorbar(im, ax=ax)

classes_label = ['No Diabetes', 'Diabetes']
tick_marks    = np.arange(len(classes_label))
ax.set_xticks(tick_marks)
ax.set_yticks(tick_marks)
ax.set_xticklabels(classes_label, fontsize=12)
ax.set_yticklabels(classes_label, fontsize=12)

# Tuliskan angka di dalam setiap kotak Confusion Matrix
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
# Simpan gambar ke file PNG
plt.savefig(CM_PATH, dpi=150)
plt.close()
print(f"  Confusion Matrix disimpan  : {CM_PATH}")


# ══════════════════════════════════════════════
# STEP 11 — VISUALISASI FEATURE IMPORTANCE (PNG)
# ══════════════════════════════════════════════
print(f"\n[STEP 11] Membuat visualisasi Feature Importance...")

# Mengambil nilai pentingnya tiap fitur dari model XGBoost
importances = best_model.feature_importances_
# Mengurutkan fitur dari skor tertinggi ke terendah
indices     = np.argsort(importances)[::-1]
feat_names  = [FITUR_KOLOM[i] for i in indices]
feat_scores = importances[indices]

# Buat grafik batang horizontal untuk visualisasi tingkat kepentingan fitur
fig, ax = plt.subplots(figsize=(8, 5))
bars = ax.barh(feat_names[::-1], feat_scores[::-1],
               color='steelblue', edgecolor='white')

# Tampilkan angka skor di samping setiap batang grafik
for bar, score in zip(bars, feat_scores[::-1]):
    ax.text(bar.get_width() + 0.002, bar.get_y() + bar.get_height() / 2,
            f'{score:.4f}', va='center', fontsize=10)

ax.set_xlabel('Importance Score', fontsize=12)
ax.set_title('Feature Importance — XGBoost\nDeteksi Dini Risiko Diabetes', fontsize=13, fontweight='bold')
ax.set_xlim(0, max(feat_scores) + 0.05)
plt.tight_layout()
# Simpan gambar grafik feature importance ke PNG
plt.savefig(FI_PATH, dpi=150)
plt.close()
print(f"  Feature Importance disimpan: {FI_PATH}")


# ══════════════════════════════════════════════
# STEP 12 — DEMONSTRASI FUNGSI PREDIKSI SIMULASI IoT
# ══════════════════════════════════════════════
print("\n[STEP 12] Demonstrasi fungsi prediksi (simulasi data dari ESP32)...")

def prediksi_risiko_diabetes(age, gender, height, weight, bmi, heart_rate, temperature_celsius):
    """
    Fungsi prediksi risiko diabetes berdasarkan parameter non-invasive dari sensor IoT ESP32.
    """
    # 1. Load artefak yang tersimpan (model, scaler, encoder)
    model   = XGBClassifier()
    model.load_model(MODEL_PATH)
    sc      = joblib.load(SCALER_PATH)
    le      = joblib.load(ENCODER_PATH)

    # 2. Enkode nilai gender ke angka
    gender_enc = le.transform([gender])[0]

    # 3. Susun array matriks masukan
    input_data = np.array([[age, gender_enc, height, weight, bmi, heart_rate, temperature_celsius]])

    # 4. Normalisasi data masukan menggunakan scaler
    input_scaled = sc.transform(input_data)

    # 5. Jalankan prediksi label & probabilitas
    label_enc = model.predict(input_scaled)[0]
    prob      = model.predict_proba(input_scaled)[0]

    label     = 'Diabetes' if label_enc == 1 else 'No Diabetes'
    prob_dm   = round(float(prob[1]) * 100, 2)
    prob_no   = round(float(prob[0]) * 100, 2)

    # 6. Tentukan saran rekomendasi dan aksi fisik pada Smart Snack Box
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


# ── Contoh Simulasi Data Input dari ESP32 ──
contoh_input = {
    'age'                  : 13,
    'gender'               : 'Male',
    'height'               : 155.0,
    'weight'               : 60.0,
    'bmi'                  : 24.97,
    'heart_rate'           : 88,          # Dari sensor MAX30102
    'temperature_celsius'  : 37.2,        # Dari sensor MLX90614
}

print(f"\n  Input data (simulasi sensor ESP32):")
for k, v in contoh_input.items():
    print(f"    {k:<25}: {v}")

# Jalankan fungsi pengujian prediksi
hasil = prediksi_risiko_diabetes(**contoh_input)

# Tampilkan hasil simulasi prediksi di konsol
print(f"\n  Hasil Prediksi:")
print(f"    Label Risiko     : {hasil['label']}")
print(f"    Probabilitas     : {hasil['probabilitas']}")
print(f"    Rekomendasi      : {hasil['rekomendasi']}")
print(f"    Aksi Snack Box   : {hasil['aksi_snack_box']}")


# ══════════════════════════════════════════════
# RINGKASAN AKHIR & CEK UKURAN FILE OUTPUT
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
