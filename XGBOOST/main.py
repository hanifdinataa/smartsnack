import argparse
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import joblib
import numpy as np
from xgboost import XGBClassifier

# Path/lokasi file model XGBoost yang sudah dilatih
MODEL_PATH = "model_xgboost.json"
# Path/lokasi file scaler (StandardScaler) untuk menormalisasi data numerik
SCALER_PATH = "scaler.pkl"
# Path/lokasi file encoder (LabelEncoder) untuk mengubah teks gender ('Male'/'Female') menjadi angka
ENCODER_PATH = "label_encoder_gender.pkl"

# Variabel global untuk menyimpan model, scaler, dan encoder setelah dimuat ke memori
model = None
scaler = None
encoder = None


# Fungsi untuk memastikan bahwa semua file artefak (model, scaler, encoder) benar-benar ada
def ensure_artifacts():
    # Cek file satu per satu, kumpulkan nama file yang tidak ditemukan
    missing = [p for p in [MODEL_PATH, SCALER_PATH, ENCODER_PATH] if not os.path.isfile(p)]
    # Jika ada file yang hilang, hentikan program dan berikan pesan error
    if missing:
        raise FileNotFoundError("Artefak model belum lengkap: " + ", ".join(missing))


# Fungsi untuk memuat (load) file model, scaler, dan encoder ke dalam variabel global
def load_artifacts():
    global model, scaler, encoder
    # Pastikan file-filenya ada terlebih dahulu
    ensure_artifacts()
    # Inisialisasi objek classifier XGBoost kosong
    xgb = XGBClassifier()
    # Muat struktur & bobot model dari file JSON
    xgb.load_model(MODEL_PATH)
    # Simpan model yang sudah dimuat ke variabel global 'model'
    model = xgb
    # Muat file scaler (.pkl) menggunakan joblib
    scaler = joblib.load(SCALER_PATH)
    # Muat file encoder gender (.pkl) menggunakan joblib
    encoder = joblib.load(ENCODER_PATH)


# Fungsi pembantu untuk mengubah nilai input menjadi tipe data float (angka desimal)
def to_float(value, field):
    try:
        # Coba konversi nilai ke float
        return float(value)
    except Exception as exc:
        # Jika gagal (misal input berupa teks sembarangan), lempar error ValueError
        raise ValueError(f"Field '{field}' harus numerik") from exc


# Fungsi untuk menormalisasi variasi tulisan jenis kelamin (Gender) menjadi 'Male' atau 'Female'
def normalize_gender(value):
    # Jika input kosong/None, secara default set ke "Male"
    if value is None:
        return "Male"
    # Ubah teks ke huruf kecil dan hapus spasi di awal/akhir
    text = str(value).strip().lower()
    # Jika teks termasuk dalam daftar opsi laki-laki
    if text in ["l", "male", "m", "laki", "laki-laki"]:
        return "Male"
    # Jika teks termasuk dalam daftar opsi perempuan
    if text in ["p", "female", "f", "perempuan", "wanita"]:
        return "Female"
    # Default jika tidak cocok dengan kriteria perempuan
    return "Male"


# Fungsi untuk menyusun data input dari API (JSON payload) menjadi vektor fitur ML
def build_feature_vector(payload):
    # 1. Ambil dan konversi 'age' (usia) ke float
    age = to_float(payload.get("age"), "age")
    # 2. Ambil 'height_cm' (atau 'height') dan konversi ke float
    height = to_float(payload.get("height_cm", payload.get("height")), "height_cm")
    # 3. Ambil 'weight_kg' (atau 'weight') dan konversi ke float
    weight = to_float(payload.get("weight_kg", payload.get("weight")), "weight_kg")
    # 4. Ambil 'heart_rate' (detak jantung dari sensor MAX30102) dan konversi ke float
    heart = to_float(payload.get("heart_rate"), "heart_rate")
    # 5. Ambil 'body_temp' (suhu tubuh dari sensor MLX90614) dan konversi ke float
    temp = to_float(payload.get("body_temp", payload.get("temperature_c")), "body_temp")

    # Validasi batas logis usia (1 - 120 tahun)
    if age <= 0 or age > 120:
        raise ValueError("age di luar rentang valid")
    # Validasi batas logis tinggi badan (50 - 260 cm)
    if height < 50 or height > 260:
        raise ValueError("height_cm di luar rentang valid")
    # Validasi batas logis berat badan (10 - 350 kg)
    if weight < 10 or weight > 350:
        raise ValueError("weight_kg di luar rentang valid")
    # Validasi batas logis detak jantung (40 - 180 bpm)
    if heart < 40 or heart > 180:
        raise ValueError("heart_rate di luar rentang valid")
    # Validasi batas logis suhu tubuh (30 - 45 derajat Celsius)
    if temp < 30 or temp > 45:
        raise ValueError("body_temp di luar rentang valid")

    # Hitung nilai BMI (Body Mass Index) jika tidak dikirim dalam payload
    bmi_val = payload.get("bmi")
    if bmi_val is None:
        # Konversi tinggi cm ke meter
        height_m = height / 100.0
        # Rumus BMI: Berat (kg) / (Tinggi (m) * Tinggi (m))
        bmi = weight / (height_m * height_m)
    else:
        # Jika nilai BMI dikirim dari API, konversi langsung ke float
        bmi = to_float(bmi_val, "bmi")

    # Normalisasi teks jenis kelamin ('Male' / 'Female')
    gender = normalize_gender(payload.get("gender"))
    # Enkode jenis kelamin menjadi angka (misal Male=1, Female=0) menggunakan encoder
    gender_enc = int(encoder.transform([gender])[0])

    # Susun 7 fitur ke dalam NumPy array 2D sesuai urutan yang dipakai saat training model:
    # [age, gender_enc, height, weight, bmi, heart, temp]
    features = np.array([[age, gender_enc, height, weight, bmi, heart, temp]], dtype=float)

    # Kembalikan array fitur untuk ML dan dictionary data bersih untuk respon API
    return features, {
        "age": int(round(age)),
        "gender": gender,
        "height_cm": round(height, 2),
        "weight_kg": round(weight, 2),
        "bmi": round(bmi, 2),
        "heart_rate": round(heart, 2),
        "body_temp": round(temp, 2),
    }


# Fungsi utama untuk melakukan prediksi risiko berdasarkan data payload
def predict_payload(payload):
    # Pastikan model, scaler, dan encoder sudah berhasil dimuat
    if model is None or scaler is None or encoder is None:
        raise RuntimeError("Model belum dimuat")

    # Susun data input menjadi vektor fitur
    features, normalized = build_feature_vector(payload)
    # Lakukan standarisasi/scaling numerik (StandardScaler) pada vektor fitur
    scaled = scaler.transform(features)

    # Lakukan prediksi label kelas (0 = Tidak Berisiko / 'no', 1 = Berisiko / 'yes')
    pred_label = int(model.predict(scaled)[0])
    # Dapatkan probabilitas/peluang untuk masing-masing kelas [prob_0, prob_1]
    probs = model.predict_proba(scaled)[0]
    # Konversi label angka (1/0) ke teks risiko ('yes' / 'no')
    risk = "yes" if pred_label == 1 else "no"

    # Kembalikan hasil prediksi lengkap dalam format Dictionary
    return {
        "risk": risk,
        "risk_diabetes": risk,
        "result": risk,
        "probability_diabetes": round(float(probs[1]), 6),    # Peluang berisiko diabetes (kelas 1)
        "probability_no_diabetes": round(float(probs[0]), 6), # Peluang tidak berisiko (kelas 0)
        "algorithm": "xgboost_model",
        "input": normalized, # Data masukan yang sudah dibersihkan
    }


# Class Handler HTTP Server untuk memproses Request yang masuk dari Backend/Client
class PredictHandler(BaseHTTPRequestHandler):
    # Fungsi pembantu untuk mengirim respon format JSON ke client
    def _send_json(self, status_code, payload):
        # Konversi dictionary Python ke string JSON lalu ke format bytes UTF-8
        body = json.dumps(payload).encode("utf-8")
        # Kirim status code HTTP (misal 200 OK, 404 Not Found, 422 Error)
        self.send_response(status_code)
        # Set header bahwa konten yang dikirim adalah JSON
        self.send_header("Content-Type", "application/json")
        # Set header panjang konten dalam byte
        self.send_header("Content-Length", str(len(body)))
        # Akhiri bagian header
        self.end_headers()
        # Tulis/kirimkan isi body JSON ke client
        self.wfile.write(body)

    # Handler untuk memproses HTTP request method POST
    def do_POST(self):
        # Jika endpoint yang dipanggil bukan '/predict', kembalikan error 404
        if self.path != "/predict":
            self._send_json(404, {"message": "Not found"})
            return

        # Baca panjang data yang dikirim client dari header Content-Length
        length = int(self.headers.get("Content-Length", "0"))
        # Baca isi data/body request sebesar 'length' bytes
        raw = self.rfile.read(length)
        try:
            # Parse data bytes menjadi object JSON/Dictionary Python
            payload = json.loads(raw.decode("utf-8"))
            # Pastikan payload bertipe dictionary/object JSON
            if not isinstance(payload, dict):
                raise ValueError("Payload harus object JSON")
            # Jalankan prediksi ML
            result = predict_payload(payload)
            # Kirim respon 200 OK beserta hasil prediksi
            self._send_json(200, result)
        except Exception as exc:
            # Jika ada kesalahan input/validasi, kirim respon error 422 Unprocessable Entity
            self._send_json(422, {"message": str(exc)})

    # Handler untuk memproses HTTP request method GET (Health Check)
    def do_GET(self):
        # Cek apakah endpoint adalah '/' atau '/health'
        if self.path in ["/", "/health"]:
            # Kirim respon 200 OK untuk menandakan service berjalan normal
            self._send_json(200, {"status": "ok", "service": "xgboost_predict_api"})
            return
        # Jika endpoint GET lainnya, kembalikan 404 Not Found
        self._send_json(404, {"message": "Not found"})

    # Matikan log bawaan HTTP server agar konsol/terminal tetap bersih
    def log_message(self, fmt, *args):
        return


# Fungsi untuk menjalankan HTTP Server pada Host & Port tertentu
def run_server(host, port):
    # Memuat file model ML terlebih dahulu sebelum server siap menerima request
    load_artifacts()
    # Buat instance ThreadingHTTPServer (mendukung request multithread/bersamaan)
    server = ThreadingHTTPServer((host, port), PredictHandler)
    # Tampilkan pesan di terminal bahwa server API sudah aktif
    print(f"XGBoost API aktif di http://{host}:{port}")
    # Jalankan server secara terus-menerus (blocking loop)
    server.serve_forever()


# Fungsi utama entrypoint program
def main():
    # Inisialisasi parser argumen terminal
    parser = argparse.ArgumentParser()
    # Opsi flag --serve (opsional/deprecated)
    parser.add_argument(
        "--serve",
        action="store_true",
        help="Deprecated: mode API sudah jadi default",
    )
    # Argumen IP host (default: 127.0.0.1)
    parser.add_argument("--host", default="127.0.0.1")
    # Argumen Port server (default: 5001)
    parser.add_argument("--port", type=int, default=5001)
    # Parse argumen dari terminal
    args = parser.parse_args()

    # Jalankan server dengan host dan port yang ditentukan
    run_server(args.host, args.port)


# Jalankan fungsi main() hanya jika script ini dieksekusi langsung (bukan di-import sebagai module)
if __name__ == "__main__":
    main()
