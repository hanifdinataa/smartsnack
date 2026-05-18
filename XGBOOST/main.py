import argparse
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import joblib
import numpy as np
from xgboost import XGBClassifier

MODEL_PATH = "model_xgboost.json"
SCALER_PATH = "scaler.pkl"
ENCODER_PATH = "label_encoder_gender.pkl"

model = None
scaler = None
encoder = None


def ensure_artifacts():
    missing = [p for p in [MODEL_PATH, SCALER_PATH, ENCODER_PATH] if not os.path.isfile(p)]
    if missing:
        raise FileNotFoundError("Artefak model belum lengkap: " + ", ".join(missing))


def load_artifacts():
    global model, scaler, encoder
    ensure_artifacts()
    xgb = XGBClassifier()
    xgb.load_model(MODEL_PATH)
    model = xgb
    scaler = joblib.load(SCALER_PATH)
    encoder = joblib.load(ENCODER_PATH)


def to_float(value, field):
    try:
        return float(value)
    except Exception as exc:
        raise ValueError(f"Field '{field}' harus numerik") from exc


def normalize_gender(value):
    if value is None:
        return "Male"
    text = str(value).strip().lower()
    if text in ["l", "male", "m", "laki", "laki-laki"]:
        return "Male"
    if text in ["p", "female", "f", "perempuan", "wanita"]:
        return "Female"
    return "Male"


def build_feature_vector(payload):
    age = to_float(payload.get("age"), "age")
    height = to_float(payload.get("height_cm", payload.get("height")), "height_cm")
    weight = to_float(payload.get("weight_kg", payload.get("weight")), "weight_kg")
    heart = to_float(payload.get("heart_rate"), "heart_rate")
    temp = to_float(payload.get("body_temp", payload.get("temperature_c")), "body_temp")

    if age <= 0 or age > 120:
        raise ValueError("age di luar rentang valid")
    if height < 50 or height > 260:
        raise ValueError("height_cm di luar rentang valid")
    if weight < 10 or weight > 350:
        raise ValueError("weight_kg di luar rentang valid")
    if heart < 40 or heart > 180:
        raise ValueError("heart_rate di luar rentang valid")
    if temp < 30 or temp > 45:
        raise ValueError("body_temp di luar rentang valid")

    bmi_val = payload.get("bmi")
    if bmi_val is None:
        height_m = height / 100.0
        bmi = weight / (height_m * height_m)
    else:
        bmi = to_float(bmi_val, "bmi")

    gender = normalize_gender(payload.get("gender"))
    gender_enc = int(encoder.transform([gender])[0])

    features = np.array([[age, gender_enc, height, weight, bmi, heart, temp]], dtype=float)
    return features, {
        "age": int(round(age)),
        "gender": gender,
        "height_cm": round(height, 2),
        "weight_kg": round(weight, 2),
        "bmi": round(bmi, 2),
        "heart_rate": round(heart, 2),
        "body_temp": round(temp, 2),
    }


def predict_payload(payload):
    if model is None or scaler is None or encoder is None:
        raise RuntimeError("Model belum dimuat")

    features, normalized = build_feature_vector(payload)
    scaled = scaler.transform(features)

    pred_label = int(model.predict(scaled)[0])
    probs = model.predict_proba(scaled)[0]
    risk = "yes" if pred_label == 1 else "no"

    return {
        "risk": risk,
        "risk_diabetes": risk,
        "result": risk,
        "probability_diabetes": round(float(probs[1]), 6),
        "probability_no_diabetes": round(float(probs[0]), 6),
        "algorithm": "xgboost_model",
        "input": normalized,
    }


class PredictHandler(BaseHTTPRequestHandler):
    def _send_json(self, status_code, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path != "/predict":
            self._send_json(404, {"message": "Not found"})
            return

        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length)
        try:
            payload = json.loads(raw.decode("utf-8"))
            if not isinstance(payload, dict):
                raise ValueError("Payload harus object JSON")
            result = predict_payload(payload)
            self._send_json(200, result)
        except Exception as exc:
            self._send_json(422, {"message": str(exc)})

    def do_GET(self):
        if self.path in ["/", "/health"]:
            self._send_json(200, {"status": "ok", "service": "xgboost_predict_api"})
            return
        self._send_json(404, {"message": "Not found"})

    def log_message(self, fmt, *args):
        return


def run_server(host, port):
    load_artifacts()
    server = ThreadingHTTPServer((host, port), PredictHandler)
    print(f"XGBoost API aktif di http://{host}:{port}")
    server.serve_forever()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--serve",
        action="store_true",
        help="Deprecated: mode API sudah jadi default",
    )
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=5001)
    args = parser.parse_args()

    run_server(args.host, args.port)


if __name__ == "__main__":
    main()
