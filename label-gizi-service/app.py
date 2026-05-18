"""
label-gizi-service
==================
Mode nutrition-only:
  - RapidOCR  - text extraction
  - Parsing   - ekstraksi gula dan berat bersih/takaran saji
"""
from __future__ import annotations

import re
import unicodedata

import cv2
import flask
import numpy as np
from rapidocr_onnxruntime import RapidOCR

app = flask.Flask(__name__)
ocr_engine = RapidOCR()


#  TEXT HELPERS

def normalize(value: str) -> str:
    # Catatan fungsi:
    # - Tujuan: menormalkan teks OCR supaya lebih mudah diproses regex.
    # - Proses: hapus aksen/karakter non-ascii, kecilkan huruf, rapikan spasi.
    # - Output: string bersih untuk kebutuhan pencocokan kata kunci.
    text = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode("ascii")
    text = re.sub(r"[^a-zA-Z0-9\s]+", " ", text).lower()
    return re.sub(r"\s+", " ", text).strip()


#  IMAGE UTILITIES

def decode_image(data: bytes) -> np.ndarray:
    # Catatan fungsi:
    # - Input: bytes gambar dari request.
    # - Proses: decode bytes -> numpy array (format BGR OpenCV).
    # - Jika gagal decode, lempar error agar endpoint memberi pesan jelas.
    img = cv2.imdecode(np.frombuffer(data, dtype=np.uint8), cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError("Gambar tidak bisa dibaca.")
    return img


def resize_image(img: np.ndarray, max_side: int = 1600) -> np.ndarray:
    # Catatan fungsi:
    # - Tujuan: membatasi ukuran gambar agar proses OCR tidak berat.
    # - Jika sisi terpanjang <= max_side, gambar dipakai apa adanya.
    # - Jika lebih besar, gambar diperkecil proporsional (aspect ratio aman).
    h, w = img.shape[:2]
    longest = max(h, w)
    if longest <= max_side:
        return img
    scale = max_side / float(longest)
    return cv2.resize(img, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_AREA)


#  PREPROCESSING VARIANTS

def _variants(img: np.ndarray) -> list[np.ndarray]:
    # Catatan fungsi:
    # - Ini generator variasi preprocessing untuk meningkatkan kemungkinan OCR berhasil.
    # - Variasi yang dipakai: original, grayscale, upscale, CLAHE, sharpen, otsu, adaptive, denoise.
    # - Strategi: nanti OCR dicoba ke semua variant, lalu dipilih hasil terbaik.
    out: list[np.ndarray] = []

    base = resize_image(img, 1200)
    out.append(base)

    gray = cv2.cvtColor(base, cv2.COLOR_BGR2GRAY)
    out.append(gray)
    out.append(cv2.resize(gray, None, fx=1.5, fy=1.5, interpolation=cv2.INTER_CUBIC))

    clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8))
    cl = clahe.apply(gray)
    out.append(cl)
    out.append(cv2.resize(cl, None, fx=1.5, fy=1.5, interpolation=cv2.INTER_CUBIC))

    blur = cv2.GaussianBlur(gray, (0, 0), 3)
    sharp = cv2.addWeighted(gray, 1.9, blur, -0.9, 0)
    out.append(sharp)

    _, otsu = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    out.append(otsu)

    adapt = cv2.adaptiveThreshold(
        gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 31, 10
    )
    out.append(adapt)

    try:
        dn = cv2.fastNlMeansDenoising(gray, h=10)
        _, dn_bin = cv2.threshold(dn, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        out.append(dn_bin)
    except Exception:
        pass

    return out


#  OCR ENGINE

def _run_ocr(img: np.ndarray) -> list[tuple[str, float]]:
    # Catatan fungsi:
    # - Jalankan RapidOCR pada satu gambar variant.
    # - Output: list tuple (teks, confidence).
    # - Jika OCR error, return [] supaya pipeline tetap lanjut tanpa crash.
    try:
        result, _ = ocr_engine(img)
        if not result:
            return []
        out = []
        for item in result:
            if len(item) < 2:
                continue
            text = str(item[1]).strip()
            conf = float(item[2]) if len(item) >= 3 else 1.0
            if text:
                out.append((text, conf))
        return out
    except Exception:
        return []


def _run_ocr_boxes(img: np.ndarray) -> list[dict]:
    # Catatan fungsi:
    # - Mirip _run_ocr, tapi simpan juga koordinat bbox tiap teks.
    # - Kenapa penting: untuk label tabel nutrisi, posisi angka biasanya sejajar dengan labelnya.
    # - Output dipakai fungsi extract_sugar_from_boxes.
    try:
        result, _ = ocr_engine(img)
        if not result:
            return []
        rows: list[dict] = []
        for item in result:
            if len(item) < 3:
                continue
            box = item[0]
            text = str(item[1]).strip()
            conf = float(item[2]) if len(item) >= 3 else 1.0
            if not text:
                continue
            xs = [int(p[0]) for p in box]
            ys = [int(p[1]) for p in box]
            rows.append(
                {
                    "text": text,
                    "norm": normalize(text),
                    "conf": conf,
                    "x": min(xs),
                    "y": min(ys),
                    "w": max(xs) - min(xs),
                    "h": max(ys) - min(ys),
                }
            )
        return rows
    except Exception:
        return []


def ocr_lines_nutrition(img: np.ndarray) -> list[str]:
    # Catatan fungsi:
    # - Menentukan hasil OCR khusus nutrisi yang paling "masuk akal".
    # - Skor dihitung dari panjang teks + jumlah keyword nutrisi yang terdeteksi.
    # - Variant dengan skor tertinggi dianggap paling representatif untuk label gizi.
    nutrition_kw = {
        "gula", "sugar", "sugars", "protein", "lemak", "fat",
        "karbohidrat", "carbohydrate", "kalori", "energi", "energy",
        "natrium", "sodium", "serat", "fiber", "vitamin",
        "takaran", "sajian", "serving",
    }

    best_lines: list[str] = []
    best_score = -1

    for idx, variant in enumerate(_variants(img)):
        pairs = _run_ocr(variant)
        text = " ".join(t for t, _ in pairs).lower()
        kw_hits = sum(1 for kw in nutrition_kw if kw in text)
        total = len(text) + kw_hits * 80
        if total > best_score:
            best_score = total
            best_lines = [t for t, _ in pairs]
        if kw_hits >= 9 and len(pairs) >= 10 and idx >= 2:
            break

    return best_lines


#  SUGAR & NET-WEIGHT EXTRACTION

_sugar_labels = r"(?:gula\s*(?:total)?|total\s*gula|sugar[s]?|total\s*sugar[s]?)"


def _fix_ocr_chars(t: str) -> str:
    # Catatan fungsi:
    # - Memperbaiki salah baca karakter OCR yang sering ganggu parsing angka.
    # - Contoh: l -> 1, O -> 0, | -> 1.
    # - Tujuan akhir: regex gula/berat tidak gagal karena typo OCR.
    t = re.sub(r"(?<=\d)l(?=\d)", "1", t)
    t = re.sub(r"\bl\b", "1", t)
    t = t.replace("|", "1")
    t = re.sub(r"(?<=[0-9])O(?=[0-9])", "0", t)
    return t


def _parse_num(s: str) -> float | None:
    # Catatan fungsi:
    # - Konversi string angka ke float.
    # - Mendukung format koma/desimal Indonesia (contoh 12,5 -> 12.5).
    # - Return None jika format tidak valid.
    try:
        return float(s.replace(",", "."))
    except ValueError:
        return None


def extract_sugar_from_boxes(img: np.ndarray) -> float | None:
    # Catatan fungsi:
    # - Prioritas utama ekstraksi gula dari OCR bbox (layout tabel).
    # - Alur:
    #   1) cari baris yang memuat kata gula/sugar
    #   2) cari kandidat angka gram di area kanan dan sejajar baris
    #   3) hindari baris sodium/natrium/garam
    #   4) pilih kandidat dengan skor tertinggi (confidence + posisi)
    # - Return nilai gram gula jika ketemu, else None.
    items = _run_ocr_boxes(img)
    if not items:
        return None

    sugar_rows = [r for r in items if re.search(r"\b(gula|sugar|sugars)\b", r["norm"], re.I)]
    if not sugar_rows:
        return None

    best_val: float | None = None
    best_score = -1.0
    for sr in sugar_rows:
        y_mid = sr["y"] + (sr["h"] / 2.0)
        y_tol = max(16.0, sr["h"] * 0.9)
        candidates = []
        for it in items:
            if it["x"] <= sr["x"]:
                continue
            if abs((it["y"] + it["h"] / 2.0) - y_mid) > y_tol:
                continue
            if re.search(r"(natrium|sodium|garam|salt)", it["norm"], re.I):
                continue
            m = re.search(r"\b(\d+(?:[.,]\d+)?)\s*(g|gr|gram)\b", it["text"], re.I)
            if m:
                val = _parse_num(m.group(1))
                if val is not None and 0 <= val <= 80:
                    score = float(it["conf"]) + (0.3 if it["x"] > sr["x"] else 0.0)
                    candidates.append((score, val))
        if candidates:
            candidates.sort(key=lambda x: x[0], reverse=True)
            if candidates[0][0] > best_score:
                best_score = candidates[0][0]
                best_val = candidates[0][1]
    return best_val


def extract_sugar(text: str) -> float | None:
    # Catatan fungsi:
    # - Fallback ekstraksi gula berbasis teks OCR mentah.
    # - Menangani 2 pola:
    #   A) inline   -> "Gula 10 g"
    #   B) tabel    -> label di satu baris, angka di baris lain
    # - Tetap ada filter agar tidak salah ambil sodium/garam.
    # - Return nilai gula (gram) jika ketemu, else None.
    compact = _fix_ocr_chars(re.sub(r"[ \t]+", " ", text))
    multiline = _fix_ocr_chars(text)

    inline_pats = [
        rf"{_sugar_labels}\s*[:\-]?\s*(\d+(?:[.,]\d+)?)\s*(?:g|gr|gram)\b",
        rf"(\d+(?:[.,]\d+)?)\s*(?:g|gr|gram)\s+{_sugar_labels}",
        rf"{_sugar_labels}\s*[:\-]?\s*(\d+(?:[.,]\d+)?)",
        r"(?:gul|sug)\w*\s*[:\-]?\s*(\d+(?:[.,]\d+)?)\s*(?:g|gr|gram)?",
    ]
    for pat in inline_pats:
        m = re.search(pat, compact, re.I)
        if m:
            val = _parse_num(m.group(m.lastindex or 1))
            if val is not None and 0 <= val <= 80:
                return val

    lines = [ln.strip() for ln in multiline.splitlines() if ln.strip()]
    for i, line in enumerate(lines):
        if re.search(_sugar_labels, line, re.I):
            scoped = re.split(r"(?:natrium|sodium|garam|salt)", line, maxsplit=1, flags=re.I)[0]
            m_same = re.search(
                rf"{_sugar_labels}[^\d]{{0,24}}(\d+(?:[.,]\d+)?)\s*(g|gr|gram)\b",
                scoped,
                re.I,
            )
            if m_same:
                val = _parse_num(m_same.group(1))
                if val is not None and 0 <= val <= 80:
                    return val

            if re.search(r"(natrium|sodium|garam|salt)", line, re.I):
                continue
            for j in range(i, min(i + 3, len(lines))):
                if re.search(r"(natrium|sodium|garam|salt)", lines[j], re.I):
                    continue
                m = re.search(r"(\d+(?:[.,]\d+)?)\s*(g|gr|gram)\b", lines[j], re.I)
                if m:
                    val = _parse_num(m.group(1))
                    if val is not None and 0 <= val <= 80:
                        return val
    return None


def extract_net_weight(text: str) -> float | None:
    # Catatan fungsi:
    # - Ekstrak berat bersih / takaran saji dari teks label.
    # - Prioritas pattern spesifik dulu (netto, net weight, serving size),
    #   lalu fallback ke pattern angka + satuan umum.
    # - Data ini konteks tambahan untuk analisis, bukan penentu utama seperti gula.
    compact = re.sub(r"[ \t]+", " ", text)

    specific_pats = [
        r"(?:takaran\s*saji|serving\s*size)\s*[:\-]?\s*(\d+(?:[.,]\d+)?)\s*(?:g|ml|gr|gram)\b",
        r"(?:berat\s*bersih|netto|isi\s*bersih|net\s*wt\.?|net\s*weight)\s*[:\-]?\s*(\d+(?:[.,]\d+)?)\s*(?:g|ml|gr|gram)\b",
    ]
    for pat in specific_pats:
        m = re.search(pat, compact, re.I)
        if m:
            v = _parse_num(m.group(1))
            if v is not None and 1 <= v <= 2000:
                return v

    for m in re.finditer(r"\b(\d+(?:[.,]\d+)?)\s*(?:g|ml|gr|gram)\b", compact, re.I):
        v = _parse_num(m.group(1))
        if v is not None and 5 <= v <= 2000:
            return v
    return None


#  MAIN DETECTION FUNCTION

def detect_nutrition(img: np.ndarray) -> dict:
    # Catatan fungsi (inti pipeline):
    # - Step 1: OCR nutrisi -> gabung jadi text.
    # - Step 2: ekstrak gula dari bbox (lebih akurat tabel).
    # - Step 3: jika gagal, fallback ekstrak gula dari text.
    # - Step 4: ekstrak net weight/takaran saji.
    # - Output: JSON siap konsumsi backend.
    # - Jika gula belum ketemu, kirim hint agar user bisa perbaiki foto.
    lines = ocr_lines_nutrition(img)
    text = "\n".join(lines)
    sugar_box = extract_sugar_from_boxes(img)
    sugar_txt = extract_sugar(text)
    sugar = sugar_box if sugar_box is not None else sugar_txt
    net_weight = extract_net_weight(text)

    hint: str | None = None
    if sugar is None:
        hint = (
            "Jumlah gula belum terbaca. "
            "Pastikan foto label gizi lurus, terang, dan tulisan 'Gula'/'Sugar' terlihat jelas."
        )

    return {
        "name": "",
        "category": "",
        "gr_sugar_content": sugar,
        "net_weight": net_weight,
        "raw_text": text,
        "label_text": text,
        "product_text": "",
        **({"hint": hint} if hint else {}),
    }


#  FLASK ENDPOINTS

def _uploaded_img() -> np.ndarray:
    # Catatan fungsi:
    # - Ambil file "image" dari form-data request.
    # - Validasi file wajib ada dan tidak kosong.
    # - Decode + resize agar langsung siap diproses pipeline OCR.
    f = flask.request.files.get("image")
    if f is None:
        raise ValueError("File image wajib diisi.")
    data = f.read()
    if not data:
        raise ValueError("File image kosong.")
    return resize_image(decode_image(data))


@app.get("/health")
def health():
    # Catatan fungsi:
    # - Endpoint pengecekan service aktif/tidak.
    # - Dipakai untuk smoke test cepat dari backend/devops.
    return flask.jsonify(
        {
            "success": True,
            "message": "ok",
            "service": "label-gizi-service",
            "mode": "nutrition-only",
        }
    )


@app.post("/detect-nutrition-label")
def detect_nutrition_label_endpoint():
    # Catatan fungsi:
    # - Endpoint utama fitur label gizi.
    # - Request: multipart/form-data dengan key "image".
    # - Response: JSON {success, data} berisi hasil ekstraksi gizi.
    # - Error ditangani agar frontend dapat pesan yang jelas.
    try:
        return flask.jsonify({"success": True, "data": detect_nutrition(_uploaded_img())})
    except Exception as exc:
        return flask.jsonify({"success": False, "message": str(exc)}), 500


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5060, debug=False)
