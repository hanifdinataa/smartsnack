// =====================================================================
//  SMART SNACK BOX — ESP32 FIRMWARE
//  Fitur:
//    - Detak Jantung  : MAX30102 (I2C: SDA=21, SCL=22)
//    - Suhu Tubuh     : MLX90614 (I2C: SDA=21, SCL=22)
//    - Berat Badan    : LoadCell 4-gauge + HX711 (DT=26, SCK=27)
//    - Tinggi Badan   : HC-SR04 ultrasonik (Trig=32, Echo=33)
//    - Servo Box      : GPIO 18 (buka otomatis 10 detik via MQTT)
//    - Buzzer         : GPIO 4
//
//  PUSH BUTTON DIHAPUS — kotak terbuka otomatis setelah
//  proses cek kesehatan berhasil di aplikasi.
//
//  PINOUT WIRING:
//  ┌─────────────────────────────────────────────┐
//  │  HX711 → ESP32                              │
//  │    VCC  → 3.3V atau 5V (Vin)               │
//  │    GND  → GND                               │
//  │    DT   → GPIO 26                           │
//  │    SCK  → GPIO 27                           │
//  ├─────────────────────────────────────────────┤
//  │  LoadCell (4-gauge full bridge) → HX711     │
//  │    Merah  (E+) → E+                         │
//  │    Hitam  (E-) → E-                         │
//  │    Putih  (A-) → A-                         │
//  │    Hijau  (A+) → A+                         │
//  ├─────────────────────────────────────────────┤
//  │  HC-SR04 → ESP32                            │
//  │    VCC  → 5V (Vin)   ← WAJIB 5V!           │
//  │    GND  → GND                               │
//  │    Trig → GPIO 32                           │
//  │    Echo → GPIO 33    (via voltage divider:  │
//  │           Echo→1kΩ→GPIO33, GPIO33→2kΩ→GND) │
//  └─────────────────────────────────────────────┘
// =====================================================================

#include <Wire.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include <ESP32Servo.h>
#include <math.h>
#include "MAX30105.h"
#include "heartRate.h"
#include <Adafruit_MLX90614.h>

// ── Library HX711 ─────────────────────────────────────────────────
// Install via Arduino Library Manager: "HX711 Arduino Library" by Bogdan Necula
// atau cari "HX711" by olkal/aguegu
#include <HX711.h>

// ===== OBJEK SENSOR & KONEKSI =====
MAX30105        particleSensor;
Adafruit_MLX90614 mlx = Adafruit_MLX90614();
HX711           scale;

WiFiClient    espClient;
PubSubClient  mqtt(espClient);
Servo         snackServo;

// ===== KONFIGURASI WIFI & MQTT =====
const char* WIFI_SSID = "RUMAHMU";
const char* WIFI_PASS = "77777777";

const char* MQTT_HOST = "54.144.6.206";
const int   MQTT_PORT = 1884;
const char* MQTT_USER = "";
const char* MQTT_PASS = "";
const char* DEVICE_ID = "esp32_health_01";

String commandTopic;
String resultTopic;
String boxOpenTopic;    // smartsnack/box/open/{device_id} — dari backend

// ===== PIN DEFINITIONS =====
const int SERVO_PIN     = 18;
const int BUZZER_PIN    = 4;
const int HX711_DT_PIN  = 26;   // LoadCell data
const int HX711_SCK_PIN = 27;   // LoadCell clock
const int HC_TRIG_PIN   = 32;   // Ultrasonik trigger
const int HC_ECHO_PIN   = 33;   // Ultrasonik echo (via voltage divider)

// ===== KONSTANTA HARDWARE =====
const unsigned long HEART_DURATION_MS           = 60000;
const int           TEMP_SAMPLES                = 25;
const int           TEMP_WARMUP_SAMPLES         = 5;
const unsigned long TEMP_SAMPLE_DELAY_MS        = 120;
const float         TEMP_CALIBRATION_OFFSET_C   = 0.3f;
const float         TEMP_MAX_DEVIATION_FROM_MEDIAN_C = 1.2f;
const long          FINGER_IR_THRESHOLD         = 8000;
const unsigned long FINGER_WAIT_TIMEOUT_MS      = 45000;
const int           SERVO_CLOSED_ANGLE          = 0;
const int           SERVO_OPEN_ANGLE            = 45;
const unsigned long SERVO_AUTO_CLOSE_MS         = 10000;  // 10 detik

// ── LoadCell ──────────────────────────────────────────────────────
// KALIBRASI: Ubah nilai ini sesuai kalibrasi kamu.
// Cara kalibrasi: letakkan benda diketahui beratnya (misal 1 kg),
// bagi raw_reading dengan berat benda → itulah CALIBRATION_FACTOR.
// Nilai negatif jika terbalik arah.
const float LOADCELL_CALIBRATION_FACTOR = -7050.0f;
const int   LOADCELL_SAMPLES            = 10;

// ── Ultrasonik (HC-SR04) ──────────────────────────────────────────
// SETUP TINGGI BADAN: sensor dipasang di LANGIT-LANGIT (menghadap ke bawah).
// Atur SENSOR_HEIGHT_CM sesuai jarak sensor ke lantai (ukur manual).
// Tinggi anak = SENSOR_HEIGHT_CM - jarak_ke_kepala
const float SENSOR_HEIGHT_CM      = 200.0f;  // Jarak sensor ke lantai (cm) — ukur sendiri!
const int   ULTRASONIC_SAMPLES    = 5;
const unsigned long HC_TIMEOUT_US = 30000;   // 30ms timeout (max ~5 meter)

// ===== STATE VARIABLES =====
unsigned long lastMqttReconnectMs = 0;
unsigned long lastMqttLoopKickMs  = 0;
unsigned long lastWifiRetryMs     = 0;
bool          servoIsOpen         = false;
unsigned long servoOpenedAtMs     = 0;
bool          mlxReady            = false;
bool          hx711Ready          = false;

// ========== FORWARD DECLARATIONS ==========
void connectMqtt();
void connectWifi();

// ========== DIAGNOSTIC HELPERS ==========
void printSeparator() { Serial.println("----------------------------------------"); }

void logNetworkDiag() {
  printSeparator();
  Serial.print("WiFi   : "); Serial.println(WiFi.status() == WL_CONNECTED ? "CONNECTED" : "DISCONNECTED");
  Serial.print("MQTT   : "); Serial.println(mqtt.connected() ? "CONNECTED" : "DISCONNECTED");
  printSeparator();
}

// ========== JSON HELPERS ==========
String jsonEscape(const String& input) {
  String out = "";
  for (size_t i = 0; i < input.length(); i++) {
    char c = input.charAt(i);
    if (c == '"' || c == '\\') { out += '\\'; out += c; }
    else if (c == '\n') out += "\\n";
    else out += c;
  }
  return out;
}

String extractJsonValue(const String& payload, const String& key) {
  String token = "\"" + key + "\"";
  int keyPos = payload.indexOf(token);
  if (keyPos < 0) return "";
  int colonPos = payload.indexOf(':', keyPos + token.length());
  if (colonPos < 0) return "";
  int start = colonPos + 1;
  while (start < (int)payload.length() && (payload[start] == ' ' || payload[start] == '\t')) start++;
  if (start >= (int)payload.length()) return "";
  if (payload[start] == '"') {
    int end = payload.indexOf('"', start + 1);
    if (end < 0) return "";
    return payload.substring(start + 1, end);
  }
  int end = start;
  while (end < (int)payload.length() && payload[end] != ',' && payload[end] != '}' && payload[end] != '\n') end++;
  return payload.substring(start, end);
}

// ========== BUZZER ==========
void beepBuzzer(unsigned long durationMs = 1000) {
  digitalWrite(BUZZER_PIN, HIGH);
  delay(durationMs);
  digitalWrite(BUZZER_PIN, LOW);
}

// ========== SENSOR INIT ==========
bool ensureMax30102Ready() {
  Wire.setClock(100000);
  delay(50);
  if (particleSensor.begin(Wire, I2C_SPEED_STANDARD)) {
    particleSensor.setup();
    particleSensor.setPulseAmplitudeRed(0x1F);
    particleSensor.setPulseAmplitudeIR(0x24);
    return true;
  }
  return false;
}

bool ensureMlxReady() {
  if (mlxReady) return true;
  const uint32_t clockSpeeds[] = {50000, 25000, 10000};
  for (int s = 0; s < 3; s++) {
    Wire.end(); delay(150);
    Wire.begin(21, 22); Wire.setClock(clockSpeeds[s]); delay(500);
    for (int attempt = 1; attempt <= 3; attempt++) {
      if (mlx.begin()) { mlxReady = true; Wire.setClock(100000); return true; }
      delay(500);
    }
  }
  Wire.setClock(100000);
  return false;
}

bool ensureHx711Ready() {
  if (hx711Ready) return scale.is_ready();
  scale.begin(HX711_DT_PIN, HX711_SCK_PIN);
  delay(500);
  if (!scale.is_ready()) {
    Serial.println("[HX711] Tidak siap. Cek kabel DT=26, SCK=27.");
    return false;
  }
  scale.set_scale(LOADCELL_CALIBRATION_FACTOR);
  scale.tare();  // Reset ke nol
  hx711Ready = true;
  Serial.println("[HX711] Siap. Tare selesai.");
  return true;
}

// ========== HEART RATE MEASUREMENT ==========
float measureHeartRateBpm(String& errorCode) {
  if (!ensureMax30102Ready()) { errorCode = "sensor_unavailable"; return 0.0f; }

  const int MAX_RATE_SAMPLES = 180;
  float rates[MAX_RATE_SAMPLES];
  int   validRates   = 0;
  long  lastBeatMs   = 0;
  int   fingerSamples = 0;
  const unsigned long WARMUP_MS = 8000;

  Serial.println("====================================================");
  Serial.println("        PEMBACAAN DETAK JANTUNG (MAX30102)");
  Serial.println("====================================================");

  long baselineTotal = 0;
  for (int i = 0; i < 40; i++) { baselineTotal += particleSensor.getIR(); delay(8); }
  long irBaseline       = baselineTotal / 40;
  long adaptiveThreshold = irBaseline + 2500;
  if (adaptiveThreshold < FINGER_IR_THRESHOLD) adaptiveThreshold = FINGER_IR_THRESHOLD;
  if (adaptiveThreshold > 25000) adaptiveThreshold = 25000;

  unsigned long fingerWaitStart = millis();
  bool          fingerDetected  = false;
  int           consecDetected  = 0;
  while (millis() - fingerWaitStart < FINGER_WAIT_TIMEOUT_MS) {
    if (mqtt.connected()) mqtt.loop();
    long irValue = particleSensor.getIR();
    if (irValue > adaptiveThreshold) {
      if (++consecDetected >= 8) { fingerDetected = true; Serial.println("Jari terdeteksi."); break; }
    } else { consecDetected = 0; }
    delay(20);
  }
  if (!fingerDetected) { Serial.println("GAGAL - Jari tidak terdeteksi."); errorCode = "finger_not_detected"; return 0.0f; }

  unsigned long startTime = millis();
  while (millis() - startTime < HEART_DURATION_MS) {
    if (mqtt.connected()) mqtt.loop(); else connectMqtt();
    long irValue = particleSensor.getIR();
    if (irValue > adaptiveThreshold) {
      fingerSamples++;
      if (checkForBeat(irValue)) {
        long nowMs = millis();
        if (lastBeatMs > 0) {
          long delta = nowMs - lastBeatMs;
          if (delta > 0) {
            float bpm = 60.0f / (delta / 1000.0f);
            if ((millis() - startTime) > WARMUP_MS && bpm >= 40.0f && bpm <= 180.0f) {
              if (validRates < MAX_RATE_SAMPLES) rates[validRates++] = bpm;
            }
          }
        }
        lastBeatMs = nowMs;
      }
    }
    delay(10);
  }

  if (fingerSamples < 100 || validRates < 12) { errorCode = "signal_invalid"; return 0.0f; }

  float sorted[MAX_RATE_SAMPLES];
  for (int i = 0; i < validRates; i++) sorted[i] = rates[i];
  for (int i = 0; i < validRates - 1; i++)
    for (int j = i + 1; j < validRates; j++)
      if (sorted[j] < sorted[i]) { float tmp = sorted[i]; sorted[i] = sorted[j]; sorted[j] = tmp; }
  float median = sorted[validRates / 2];

  float total = 0.0f; int used = 0;
  for (int i = 0; i < validRates; i++)
    if (fabsf(rates[i] - median) <= 15.0f) { total += rates[i]; used++; }

  if (used < 8) { errorCode = "signal_invalid"; return 0.0f; }
  float avgBpm = total / used;
  if (avgBpm < 45.0f || avgBpm > 180.0f) { errorCode = "signal_invalid"; return 0.0f; }

  Serial.print("Detak Jantung : "); Serial.print(avgBpm, 2); Serial.println(" BPM");
  return avgBpm;
}

// ========== BODY TEMPERATURE MEASUREMENT ==========
float measureBodyTemperatureC(String& errorCode) {
  if (!ensureMlxReady()) { errorCode = "sensor_unavailable"; return 0.0f; }

  Serial.println("====================================================");
  Serial.println("        PENGUKURAN SUHU TUBUH (MLX90614)");
  Serial.println("====================================================");

  for (int i = 0; i < TEMP_WARMUP_SAMPLES; i++) {
    if (mqtt.connected()) mqtt.loop(); else connectMqtt();
    float warmObj = mlx.readObjectTempC();
    float warmAmb = mlx.readAmbientTempC();
    if (isnan(warmObj) && isnan(warmAmb)) { mlxReady = false; errorCode = "sensor_unavailable"; return 0.0f; }
    delay(TEMP_SAMPLE_DELAY_MS);
  }

  float readings[TEMP_SAMPLES]; int count = 0;
  for (int i = 0; i < TEMP_SAMPLES; i++) {
    if (mqtt.connected()) mqtt.loop(); else connectMqtt();
    float obj = mlx.readObjectTempC(); float amb = mlx.readAmbientTempC();
    if (isnan(obj) && isnan(amb)) { mlxReady = false; errorCode = "sensor_unavailable"; return 0.0f; }
    float t = !isnan(obj) ? obj : amb;
    if (!isnan(t) && t >= 20.0f && t <= 50.0f) readings[count++] = t;
    delay(TEMP_SAMPLE_DELAY_MS);
  }

  if (count < 8) { errorCode = "signal_invalid"; return 0.0f; }
  for (int i = 0; i < count - 1; i++)
    for (int j = i + 1; j < count; j++)
      if (readings[j] < readings[i]) { float tmp = readings[i]; readings[i] = readings[j]; readings[j] = tmp; }

  float median = readings[count / 2];
  float total  = 0.0f; int used = 0;
  for (int i = 0; i < count; i++)
    if (fabsf(readings[i] - median) <= TEMP_MAX_DEVIATION_FROM_MEDIAN_C) { total += readings[i]; used++; }

  if (used < 5) { errorCode = "signal_invalid"; return 0.0f; }
  float calibrated = (total / used) + TEMP_CALIBRATION_OFFSET_C;
  Serial.print("Suhu Tubuh : "); Serial.print(calibrated, 2); Serial.println(" °C");
  return calibrated;
}

// ========== WEIGHT MEASUREMENT (LOADCELL HX711) ==========
float measureWeightKg(String& errorCode) {
  Serial.println("====================================================");
  Serial.println("        PENGUKURAN BERAT BADAN (HX711)");
  Serial.println("====================================================");

  if (!ensureHx711Ready()) {
    errorCode = "sensor_unavailable";
    return 0.0f;
  }

  Serial.println("Membaca berat badan...");
  if (mqtt.connected()) mqtt.loop();

  // Baca rata-rata dari beberapa sampel
  float totalWeight = 0.0f;
  int   validCount  = 0;
  for (int i = 0; i < LOADCELL_SAMPLES; i++) {
    if (scale.is_ready()) {
      float w = scale.get_units(1);
      if (!isnan(w) && fabsf(w) < 300.0f) {  // filter outlier
        totalWeight += w;
        validCount++;
      }
    }
    delay(100);
    if (mqtt.connected()) mqtt.loop();
  }

  if (validCount < 3) {
    Serial.println("GAGAL - Tidak cukup sampel valid dari LoadCell.");
    errorCode = "signal_invalid";
    return 0.0f;
  }

  float avgWeight = totalWeight / validCount;
  // Pastikan positif (kalau negatif, balik CALIBRATION_FACTOR)
  if (avgWeight < 0) avgWeight = fabsf(avgWeight);
  // Filter range realistis
  if (avgWeight < 1.0f || avgWeight > 200.0f) {
    Serial.print("GAGAL - Berat tidak valid: "); Serial.println(avgWeight);
    errorCode = "signal_invalid";
    return 0.0f;
  }

  Serial.print("Berat Badan : "); Serial.print(avgWeight, 2); Serial.println(" kg");
  return avgWeight;
}

// ========== HEIGHT MEASUREMENT (HC-SR04 ULTRASONIC) ==========
// Sensor dipasang di atas, menghadap ke bawah (langit-langit / frame).
// Tinggi anak = SENSOR_HEIGHT_CM - jarak_pantulan
float measureHeightCm(String& errorCode) {
  Serial.println("====================================================");
  Serial.println("        PENGUKURAN TINGGI BADAN (HC-SR04)");
  Serial.println("====================================================");

  // Baca beberapa sampel, ambil median
  float samples[ULTRASONIC_SAMPLES];
  int   validCount = 0;

  for (int i = 0; i < ULTRASONIC_SAMPLES; i++) {
    // Kirim pulse 10µs ke Trig
    digitalWrite(HC_TRIG_PIN, LOW);
    delayMicroseconds(2);
    digitalWrite(HC_TRIG_PIN, HIGH);
    delayMicroseconds(10);
    digitalWrite(HC_TRIG_PIN, LOW);

    // Baca durasi Echo
    unsigned long duration = pulseIn(HC_ECHO_PIN, HIGH, HC_TIMEOUT_US);
    if (duration == 0) {
      Serial.println("[HC-SR04] Timeout.");
      delay(60);
      continue;
    }

    // Jarak = (duration * kecepatan_suara) / 2
    // Kecepatan suara ~343 m/s = 0.0343 cm/µs
    float distanceCm = (duration * 0.0343f) / 2.0f;

    // Filter range valid (5–250 cm)
    if (distanceCm >= 5.0f && distanceCm <= 250.0f) {
      samples[validCount++] = distanceCm;
    }
    delay(60);
    if (mqtt.connected()) mqtt.loop();
  }

  if (validCount < 2) {
    Serial.println("GAGAL - Tidak cukup sampel dari HC-SR04.");
    errorCode = "signal_invalid";
    return 0.0f;
  }

  // Sort & median
  for (int i = 0; i < validCount - 1; i++)
    for (int j = i + 1; j < validCount; j++)
      if (samples[j] < samples[i]) { float tmp = samples[i]; samples[i] = samples[j]; samples[j] = tmp; }
  float medianDist = samples[validCount / 2];

  // Tinggi badan = tinggi sensor dari lantai - jarak pantulan ke kepala
  float heightCm = SENSOR_HEIGHT_CM - medianDist;

  if (heightCm < 50.0f || heightCm > 250.0f) {
    Serial.print("GAGAL - Tinggi tidak valid: "); Serial.println(heightCm);
    errorCode = "signal_invalid";
    return 0.0f;
  }

  Serial.print("Jarak ke kepala : "); Serial.print(medianDist, 2); Serial.println(" cm");
  Serial.print("Tinggi Badan    : "); Serial.print(heightCm, 2); Serial.println(" cm");
  return heightCm;
}

// ========== PUBLISH FUNCTIONS ==========
void publishError(const String& checkId, const String& action, const String& errorCode) {
  String payload = "{";
  payload += "\"status\":\"error\",";
  payload += "\"action\":\"" + jsonEscape(action) + "\",";
  payload += "\"check_id\":" + checkId + ",";
  payload += "\"error\":\"" + jsonEscape(errorCode) + "\",";
  payload += "\"device_id\":\"" + jsonEscape(DEVICE_ID) + "\"";
  payload += "}";
  for (int i = 0; i < 3; i++) {
    if (!mqtt.connected()) connectMqtt();
    if (mqtt.publish(resultTopic.c_str(), payload.c_str())) break;
    delay(120); mqtt.loop();
  }
}

void publishHeartRate(const String& checkId, float bpm) {
  String payload = "{";
  payload += "\"status\":\"ok\",";
  payload += "\"action\":\"heart_rate\",";
  payload += "\"check_id\":" + checkId + ",";
  payload += "\"heart_rate\":" + String(bpm, 2) + ",";
  payload += "\"device_id\":\"" + jsonEscape(DEVICE_ID) + "\"";
  payload += "}";
  for (int i = 0; i < 3; i++) {
    if (!mqtt.connected()) connectMqtt();
    if (mqtt.publish(resultTopic.c_str(), payload.c_str())) { beepBuzzer(500); break; }
    delay(120); mqtt.loop();
  }
  Serial.print("[MQTT] HeartRate published: "); Serial.println(bpm, 2);
}

void publishBodyTemperature(const String& checkId, float temp) {
  String payload = "{";
  payload += "\"status\":\"ok\",";
  payload += "\"action\":\"body_temperature\",";
  payload += "\"check_id\":" + checkId + ",";
  payload += "\"body_temp\":" + String(temp, 2) + ",";
  payload += "\"device_id\":\"" + jsonEscape(DEVICE_ID) + "\"";
  payload += "}";
  for (int i = 0; i < 3; i++) {
    if (!mqtt.connected()) connectMqtt();
    if (mqtt.publish(resultTopic.c_str(), payload.c_str())) { beepBuzzer(500); break; }
    delay(120); mqtt.loop();
  }
  Serial.print("[MQTT] BodyTemp published: "); Serial.println(temp, 2);
}

void publishWeight(const String& checkId, float weightKg) {
  String payload = "{";
  payload += "\"status\":\"ok\",";
  payload += "\"action\":\"weight\",";
  payload += "\"check_id\":" + checkId + ",";
  payload += "\"weight_kg\":" + String(weightKg, 2) + ",";
  payload += "\"device_id\":\"" + jsonEscape(DEVICE_ID) + "\"";
  payload += "}";
  for (int i = 0; i < 3; i++) {
    if (!mqtt.connected()) connectMqtt();
    if (mqtt.publish(resultTopic.c_str(), payload.c_str())) { beepBuzzer(500); break; }
    delay(120); mqtt.loop();
  }
  Serial.print("[MQTT] Weight published: "); Serial.println(weightKg, 2);
}

void publishHeight(const String& checkId, float heightCm) {
  String payload = "{";
  payload += "\"status\":\"ok\",";
  payload += "\"action\":\"height\",";
  payload += "\"check_id\":" + checkId + ",";
  payload += "\"height_cm\":" + String(heightCm, 2) + ",";
  payload += "\"device_id\":\"" + jsonEscape(DEVICE_ID) + "\"";
  payload += "}";
  for (int i = 0; i < 3; i++) {
    if (!mqtt.connected()) connectMqtt();
    if (mqtt.publish(resultTopic.c_str(), payload.c_str())) { beepBuzzer(500); break; }
    delay(120); mqtt.loop();
  }
  Serial.print("[MQTT] Height published: "); Serial.println(heightCm, 2);
}

// ========== COMMAND HANDLER ==========
void handleCommandPayload(const String& payload) {
  String action  = extractJsonValue(payload, "action");
  String checkId = extractJsonValue(payload, "check_id");
  action.trim(); checkId.trim();
  if (checkId.length() == 0) checkId = "0";

  printSeparator();
  Serial.print("[MQTT] Command: action="); Serial.print(action);
  Serial.print(" | check_id="); Serial.println(checkId);

  String errorCode = "";

  if (action == "heart_rate") {
    float bpm = measureHeartRateBpm(errorCode);
    if (errorCode.length() > 0) { publishError(checkId, action, errorCode); return; }
    publishHeartRate(checkId, bpm);
    return;
  }

  if (action == "body_temperature") {
    float temp = measureBodyTemperatureC(errorCode);
    if (errorCode.length() > 0) { publishError(checkId, action, errorCode); return; }
    publishBodyTemperature(checkId, temp);
    return;
  }

  if (action == "weight") {
    float w = measureWeightKg(errorCode);
    if (errorCode.length() > 0) { publishError(checkId, action, errorCode); return; }
    publishWeight(checkId, w);
    return;
  }

  if (action == "height") {
    float h = measureHeightCm(errorCode);
    if (errorCode.length() > 0) { publishError(checkId, action, errorCode); return; }
    publishHeight(checkId, h);
    return;
  }

  publishError(checkId, action, "unknown_action");
}

// ========== SERVO CONTROL ==========
void openServo() {
  snackServo.write(SERVO_OPEN_ANGLE);
  servoIsOpen     = true;
  servoOpenedAtMs = millis();
  Serial.println("[SERVO] Box terbuka! Auto-close dalam 10 detik.");
  // Bunyi panjang sebagai hadiah
  beepBuzzer(300); delay(100); beepBuzzer(300); delay(100); beepBuzzer(300);
}

void closeServoIfNeeded() {
  if (!servoIsOpen) return;
  if (millis() - servoOpenedAtMs < SERVO_AUTO_CLOSE_MS) return;
  snackServo.write(SERVO_CLOSED_ANGLE);
  servoIsOpen = false;
  Serial.println("[SERVO] Box tertutup otomatis.");
}

// ========== HANDLE BOX OPEN (dari backend setelah cek kesehatan) ==========
void handleBoxOpenPayload(const String& payload) {
  printSeparator();
  Serial.println("[BOX] Perintah buka box diterima dari backend.");
  String event = extractJsonValue(payload, "event");
  Serial.print("[BOX] Event: "); Serial.println(event);

  if (!servoIsOpen) {
    openServo();
  } else {
    // Reset timer jika sudah terbuka
    servoOpenedAtMs = millis();
    Serial.println("[BOX] Box sudah terbuka, timer direset ke 10 detik.");
  }
  printSeparator();
}

// ========== MQTT CALLBACK ==========
void mqttCallback(char* topic, byte* payload, unsigned int length) {
  String message = "";
  for (unsigned int i = 0; i < length; i++) message += (char)payload[i];
  String incomingTopic = String(topic);
  Serial.print("[MQTT] Pesan dari: "); Serial.println(incomingTopic);

  if (incomingTopic == commandTopic) { handleCommandPayload(message); return; }
  if (incomingTopic == boxOpenTopic) { handleBoxOpenPayload(message); return; }
}

// ========== WIFI & MQTT ==========
void connectWifi() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  unsigned long startMs = millis();
  while (WiFi.status() != WL_CONNECTED && (millis() - startMs) < 20000) delay(500);
  if (WiFi.status() == WL_CONNECTED) { logNetworkDiag(); }
  else { Serial.println("[WiFi] Gagal terhubung."); }
}

void connectMqtt() {
  if (mqtt.connected()) return;
  String clientId = String("esp32_") + DEVICE_ID + "_" + String((uint32_t)ESP.getEfuseMac(), HEX);
  Serial.println("[MQTT] Connecting...");
  bool ok = strlen(MQTT_USER) > 0
            ? mqtt.connect(clientId.c_str(), MQTT_USER, MQTT_PASS)
            : mqtt.connect(clientId.c_str());
  if (ok) {
    Serial.println("[MQTT] Connected");
    mqtt.subscribe(commandTopic.c_str());
    mqtt.subscribe(boxOpenTopic.c_str());
  } else {
    Serial.print("[MQTT] Failed rc="); Serial.println(mqtt.state());
  }
}

// ========== SETUP ==========
void setup() {
  Serial.begin(115200);
  delay(1200);

  // ── I2C Init ──────────────────────────────────────────────────
  Wire.begin(21, 22);
  Wire.setClock(50000);
  delay(500);

  // ── MAX30102 Init ─────────────────────────────────────────────
  Wire.setClock(100000);
  bool maxOk = false;
  for (int attempt = 1; attempt <= 3; attempt++) {
    if (particleSensor.begin(Wire, I2C_SPEED_STANDARD)) { maxOk = true; break; }
    delay(500);
  }
  if (!maxOk) {
    Serial.println("[ERROR] MAX30102 tidak ditemukan! Cek koneksi I2C.");
    // Tidak halt — bisa lanjut tanpa MAX30102
  } else {
    particleSensor.setup();
    particleSensor.setPulseAmplitudeRed(0x1F);
    particleSensor.setPulseAmplitudeIR(0x24);
    Serial.println("[MAX30102] OK");
  }

  // ── MLX90614 Init ─────────────────────────────────────────────
  Wire.setClock(50000);
  delay(300);
  for (int attempt = 1; attempt <= 5; attempt++) {
    if (mlx.begin()) { mlxReady = true; break; }
    delay(500);
  }
  Wire.setClock(100000);
  Serial.print("[MLX90614] "); Serial.println(mlxReady ? "OK" : "Tidak ditemukan");

  // ── HX711 (LoadCell) Init ─────────────────────────────────────
  scale.begin(HX711_DT_PIN, HX711_SCK_PIN);
  delay(500);
  if (scale.is_ready()) {
    scale.set_scale(LOADCELL_CALIBRATION_FACTOR);
    scale.tare();
    hx711Ready = true;
    Serial.println("[HX711] OK - Tare selesai.");
  } else {
    Serial.println("[HX711] Tidak siap. Cek kabel DT=26, SCK=27.");
  }

  // ── HC-SR04 (Ultrasonik) Init ─────────────────────────────────
  pinMode(HC_TRIG_PIN, OUTPUT);
  pinMode(HC_ECHO_PIN, INPUT);
  digitalWrite(HC_TRIG_PIN, LOW);
  Serial.println("[HC-SR04] Pin configured. Trig=32, Echo=33.");
  Serial.print("[HC-SR04] Sensor height from floor = "); Serial.print(SENSOR_HEIGHT_CM); Serial.println(" cm");

  // ── MQTT Topics ───────────────────────────────────────────────
  commandTopic = String("smartsnack/health/command/") + DEVICE_ID;
  resultTopic  = String("smartsnack/health/result/")  + DEVICE_ID;
  boxOpenTopic = String("smartsnack/box/open/")        + DEVICE_ID;

  // ── Servo Init ────────────────────────────────────────────────
  snackServo.setPeriodHertz(50);
  snackServo.attach(SERVO_PIN, 500, 2400);
  snackServo.write(SERVO_CLOSED_ANGLE);

  // ── Buzzer Init ───────────────────────────────────────────────
  pinMode(BUZZER_PIN, OUTPUT);
  digitalWrite(BUZZER_PIN, LOW);

  // ── Network Init ──────────────────────────────────────────────
  connectWifi();
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  mqtt.setCallback(mqttCallback);
  mqtt.setBufferSize(1024);
  mqtt.setKeepAlive(120);
  mqtt.setSocketTimeout(15);
  connectMqtt();

  printSeparator();
  Serial.println("System Ready — Smart Snack Box v2.0");
  Serial.println("Topics:");
  Serial.print("  Command : "); Serial.println(commandTopic);
  Serial.print("  Result  : "); Serial.println(resultTopic);
  Serial.print("  Box Open: "); Serial.println(boxOpenTopic);
  printSeparator();
  beepBuzzer(200);
}

// ========== LOOP ==========
void loop() {
  // WiFi reconnect
  if (WiFi.status() != WL_CONNECTED) {
    if (millis() - lastWifiRetryMs > 5000) {
      lastWifiRetryMs = millis();
      connectWifi();
    }
    delay(20);
    return;
  }

  // MQTT reconnect & loop
  if (!mqtt.connected()) {
    if (millis() - lastMqttReconnectMs > 3000) {
      lastMqttReconnectMs = millis();
      connectMqtt();
    }
  } else {
    mqtt.loop();
    if (millis() - lastMqttLoopKickMs > 5000) {
      lastMqttLoopKickMs = millis();
      // Periodic status print (tidak spam)
    }
  }

  // Auto-close servo setelah 10 detik
  closeServoIfNeeded();
}
