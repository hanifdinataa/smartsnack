#include <Wire.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include <ESP32Servo.h>
#include <Adafruit_MLX90614.h>
#include "MAX30105.h"
#include "heartRate.h"
#include <NewPing.h>
#include "HX711.h"
#include <LiquidCrystal_I2C.h>

// ===== KONFIGURASI PIN =====
#define TRIG_PIN       26
#define ECHO_PIN       27
#define HX711_DT_PIN   32
#define HX711_SCK_PIN  33
#define SERVO_PIN      18
#define BUZZER_PIN     19

// ===== ALAMAT I2C & SENSOR =====
LiquidCrystal_I2C lcd(0x27, 16, 2);
NewPing           sonar(TRIG_PIN, ECHO_PIN, 400);
Adafruit_MLX90614 mlx;
MAX30105          particleSensor;
HX711             scale;
Servo             snackServo;

WiFiClient        espClient;
PubSubClient      mqtt(espClient);

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
String boxOpenTopic;

// ===== KALIBRASI SENSOR =====
const float SENSOR_HEIGHT_CM      = 174.0f;
const float BODY_TEMP_OFFSET      = 1.2f;
// Faktor kalibrasi HX711 (nilai dasar, jangan diubah)
const float CALIBRATION_FACTOR    = 7050.0f;

// ─── KALIBRASI 2 TITIK LINIER (PRESISI TINGGI) ────────────────────────
//  Rumus: actual_kg = (raw_val - WEIGHT_OFFSET) / WEIGHT_SLOPE
//  Data Kalibrasi Fisik Aktual:
//    - BB Asli 42 kg -> Terbaca mentah (raw) 121.28
//    - BB Asli 66 kg -> Terbaca mentah (raw) 198.21
//  Hasil Perhitungan:
//    - WEIGHT_SLOPE  = (198.21 - 121.28) / (66.0 - 42.0) = 3.205f
//    - WEIGHT_OFFSET = 121.28 - (3.205 * 42.0) = -13.35f
const float WEIGHT_SLOPE          = 3.205f;
const float WEIGHT_OFFSET         = -13.35f;
//  Jika nilai raw di bawah threshold ini, timbangan dianggap kosong
const float WEIGHT_RAW_THRESHOLD  = 15.0f;

const int   SERVO_CLOSED_ANGLE    = 0;
const int   SERVO_OPEN_ANGLE      = 90;
const unsigned long SERVO_AUTO_CLOSE_MS = 10000; // 10 Detik

// ===== STATE VARIABLES =====
unsigned long lastMqttReconnectMs = 0;
unsigned long lastWifiRetryMs     = 0;
bool          servoIsOpen         = false;
unsigned long servoOpenedAtMs     = 0;
float         beratGlobal         = 0.0f;
bool          isMeasuring         = false;  // Cegah re-entrancy MQTT callback

// BPM Helper variables
const byte RATE_SIZE = 4;
byte rates[RATE_SIZE];
byte rateSpot = 0;
long lastBeat = 0;
float bpm = 0;
int beatAvg = 0;

// LCD & Serial timing
unsigned long lastPrintMs = 0;
unsigned long lastLcdPageMs = 0;
byte lcdPage = 0;

// ========== FORWARD DECLARATIONS ==========
void connectMqtt();
void connectWifi();

// ========== BUZZER HELPER ==========
void beepBuzzer(unsigned long durationMs = 300) {
  digitalWrite(BUZZER_PIN, HIGH);
  delay(durationMs);
  digitalWrite(BUZZER_PIN, LOW);
}

// ========== READERS ==========
float readDistance() {
  unsigned int u = sonar.ping();
  if (u == 0) return -1;
  float d = u / 58.0f;
  if (d >= 2 && d <= 400) return d;
  return -1;
}

// ========== MEASUREMENT FUNCTIONS FOR MQTT / FLUTTER ==========

float measureHeartRateBpm(String& errorCode) {
  Serial.println(">>> Pengukuran Detak Jantung via Aplikasi <<<");
  unsigned long startTime = millis();
  int validBeats = 0;
  
  // Baca selama 60 detik untuk akurasi
  while (millis() - startTime < 60000) {
    // Panggil mqtt.loop() agar koneksi MQTT tetap hidup selama pengukuran
    if (mqtt.connected()) mqtt.loop();
    long ir = particleSensor.getIR();
    if (ir > 50000) {
      if (checkForBeat(ir)) {
        long delta = millis() - lastBeat;
        lastBeat = millis();
        float currentBpm = 60.0f / (delta / 1000.0f);
        if (currentBpm > 40 && currentBpm < 200) {
          rates[rateSpot++] = (byte)currentBpm;
          rateSpot %= RATE_SIZE;
          validBeats++;
        }
      }
    }
    delay(10);
  }

  // Hitung rata-rata
  int totalRates = 0, validCount = 0;
  for (byte i = 0; i < RATE_SIZE; i++) {
    if (rates[i] > 0) {
      totalRates += rates[i];
      validCount++;
    }
  }

  if (validCount == 0 || validBeats < 2) {
    errorCode = "finger_not_detected";
    return 0.0f;
  }

  beatAvg = totalRates / validCount;
  Serial.print("Hasil BPM: "); Serial.println(beatAvg);
  return (float)beatAvg;
}

float measureBodyTemperatureC(String& errorCode) {
  Serial.println(">>> Pengukuran Suhu Tubuh via Aplikasi <<<");
  float totalTemp = 0.0f;
  int count = 0;
  // Pengambilan sampel selama 3 detik (30 x 100ms)
  for (int i = 0; i < 30; i++) {
    // Panggil mqtt.loop() agar koneksi MQTT tetap hidup selama pengukuran
    if (mqtt.connected()) mqtt.loop();
    float t = mlx.readObjectTempC();
    if (!isnan(t) && t > 20.0f && t < 50.0f) {
      totalTemp += t;
      count++;
    }
    delay(100);
  }

  if (count == 0) {
    errorCode = "sensor_unavailable";
    return 0.0f;
  }

  float avgTemp = (totalTemp / count) + BODY_TEMP_OFFSET;
  Serial.print("Hasil Suhu: "); Serial.println(avgTemp, 1);
  return avgTemp;
}

float measureWeightKg(String& errorCode) {
  Serial.println(">>> Pengukuran Berat Badan via Aplikasi <<<");

  // Tunggu HX711 siap (maks 2 detik)
  unsigned long startWait = millis();
  while (!scale.is_ready() && (millis() - startWait < 2000)) {
    delay(10);
  }

  // Ambil 5 sampel cepat
  float samples[5];
  int count = 0;
  for (int i = 0; i < 5; i++) {
    if (scale.is_ready()) {
      float raw = scale.get_units(1);
      Serial.printf("  Sample %d: raw = %.2f\n", i, raw);
      samples[count++] = raw;
    } else {
      Serial.printf("  Sample %d: NOT READY\n", i);
    }
    delay(20);
  }

  if (count == 0) {
    Serial.println("  No valid samples, returning beratGlobal");
    return beratGlobal;
  }

  // Bubble sort untuk mencari median (menghilangkan noise spike)
  for (int i = 0; i < count - 1; i++) {
    for (int j = i + 1; j < count; j++) {
      if (samples[j] < samples[i]) {
        float tmp = samples[i];
        samples[i] = samples[j];
        samples[j] = tmp;
      }
    }
  }

  float rawMedian = samples[count / 2];

  float corrected = 0.0f;
  if (rawMedian >= WEIGHT_RAW_THRESHOLD) {
    corrected = (rawMedian - WEIGHT_OFFSET) / WEIGHT_SLOPE;
  }

  // Update agar LCD dan Serial print sinkron seketika
  beratGlobal = corrected;

  Serial.printf("Raw Median: %.2f | Aktual: %.2f kg\n", rawMedian, corrected);
  return corrected;
}

float measureHeightCm(String& errorCode) {
  Serial.println(">>> Pengukuran Tinggi Badan via Aplikasi <<<");
  float dist = readDistance();
  if (dist < 0) {
    errorCode = "signal_invalid";
    return 0.0f;
  }
  float tinggi = SENSOR_HEIGHT_CM - dist;
  if (tinggi < 0) tinggi = 0;
  Serial.print("Hasil Tinggi: "); Serial.println(tinggi, 1);
  return tinggi;
}

// ========== MQTT PUBLISH HELPERS ==========
void publishError(const String& checkId, const String& action, const String& errorCode) {
  connectMqtt();
  String payload = "{\"status\":\"error\",\"action\":\"" + action + "\",\"check_id\":" + checkId + ",\"error\":\"" + errorCode + "\",\"device_id\":\"" + DEVICE_ID + "\"}";
  mqtt.publish(resultTopic.c_str(), payload.c_str());
}

void publishHeartRate(const String& checkId, float bpmVal) {
  connectMqtt();
  String payload = "{\"status\":\"ok\",\"action\":\"heart_rate\",\"check_id\":" + checkId + ",\"heart_rate\":" + String(bpmVal, 1) + ",\"device_id\":\"" + DEVICE_ID + "\"}";
  mqtt.publish(resultTopic.c_str(), payload.c_str());
  beepBuzzer(200);
}

void publishBodyTemperature(const String& checkId, float tempVal) {
  connectMqtt();
  String payload = "{\"status\":\"ok\",\"action\":\"body_temperature\",\"check_id\":" + checkId + ",\"body_temp\":" + String(tempVal, 1) + ",\"device_id\":\"" + DEVICE_ID + "\"}";
  mqtt.publish(resultTopic.c_str(), payload.c_str());
  beepBuzzer(200);
}

void publishWeight(const String& checkId, float weightVal) {
  connectMqtt();
  String payload = "{\"status\":\"ok\",\"action\":\"weight\",\"check_id\":" + checkId + ",\"weight_kg\":" + String(weightVal, 2) + ",\"device_id\":\"" + DEVICE_ID + "\"}";
  mqtt.publish(resultTopic.c_str(), payload.c_str());
}

void publishHeight(const String& checkId, float heightVal) {
  connectMqtt();
  String payload = "{\"status\":\"ok\",\"action\":\"height\",\"check_id\":" + checkId + ",\"height_cm\":" + String(heightVal, 1) + ",\"device_id\":\"" + DEVICE_ID + "\"}";
  mqtt.publish(resultTopic.c_str(), payload.c_str());
  beepBuzzer(200);
}

// ========== SERVO CONTROL ==========
void openServo() {
  snackServo.write(SERVO_OPEN_ANGLE);
  servoIsOpen = true;
  servoOpenedAtMs = millis();
  Serial.println("[SERVO] Box terbuka! Auto-close dalam 10 detik.");
  beepBuzzer(250); delay(100); beepBuzzer(250);
}

void closeServoIfNeeded() {
  if (!servoIsOpen) return;
  if (millis() - servoOpenedAtMs >= SERVO_AUTO_CLOSE_MS) {
    snackServo.write(SERVO_CLOSED_ANGLE);
    servoIsOpen = false;
    Serial.println("[SERVO] Box tertutup otomatis.");
  }
}

// ========== MQTT COMMAND HANDLER ==========
void handleCommandPayload(const String& payload) {
  int actionPos = payload.indexOf("\"action\":\"");
  if (actionPos < 0) return;
  int actionStart = actionPos + 10;
  int actionEnd = payload.indexOf("\"", actionStart);
  String action = payload.substring(actionStart, actionEnd);

  int checkIdPos = payload.indexOf("\"check_id\":");
  String checkId = "0";
  if (checkIdPos >= 0) {
    int idStart = checkIdPos + 11;
    int idEnd = payload.indexOf(",", idStart);
    if (idEnd < 0) idEnd = payload.indexOf("}", idStart);
    checkId = payload.substring(idStart, idEnd);
    checkId.trim();
  }

  Serial.printf("[MQTT Command] Action: %s | Check ID: %s\n", action.c_str(), checkId.c_str());
  String errorCode = "";

  if (action == "heart_rate") {
    float bpmVal = measureHeartRateBpm(errorCode);
    if (errorCode.length() > 0) publishError(checkId, action, errorCode);
    else publishHeartRate(checkId, bpmVal);
  } else if (action == "body_temperature") {
    float tempVal = measureBodyTemperatureC(errorCode);
    if (errorCode.length() > 0) publishError(checkId, action, errorCode);
    else publishBodyTemperature(checkId, tempVal);
  } else if (action == "weight") {
    float weightVal = measureWeightKg(errorCode);
    if (errorCode.length() > 0) publishError(checkId, action, errorCode);
    else publishWeight(checkId, weightVal);
  } else if (action == "height") {
    float heightVal = measureHeightCm(errorCode);
    if (errorCode.length() > 0) publishError(checkId, action, errorCode);
    else publishHeight(checkId, heightVal);
  }
}

void mqttCallback(char* topic, byte* payload, unsigned int length) {
  String message = "";
  for (unsigned int i = 0; i < length; i++) message += (char)payload[i];
  String incomingTopic = String(topic);

  if (incomingTopic == commandTopic) {
    if (isMeasuring) {
      // Abaikan perintah baru jika sedang mengukur (cegah re-entrancy)
      Serial.println("[MQTT] Perintah diabaikan: sedang mengukur.");
      return;
    }
    isMeasuring = true;
    handleCommandPayload(message);
    isMeasuring = false;
  } else if (incomingTopic == boxOpenTopic) {
    openServo();
  }
}

// ========== NETWORK CONNECTIONS ==========
void connectWifi() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  unsigned long startMs = millis();
  while (WiFi.status() != WL_CONNECTED && (millis() - startMs) < 15000) delay(500);
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("[WiFi] Terhubung! IP: " + WiFi.localIP().toString());
  } else {
    Serial.println("[WiFi] Gagal Terhubung.");
  }
}

void connectMqtt() {
  if (mqtt.connected()) return;
  String clientId = String("esp32_") + DEVICE_ID;
  if (mqtt.connect(clientId.c_str(), MQTT_USER, MQTT_PASS)) {
    Serial.println("[MQTT] Terhubung ke Broker!");
    mqtt.subscribe(commandTopic.c_str());
    mqtt.subscribe(boxOpenTopic.c_str());
  } else {
    Serial.print("[MQTT] Gagal konek, rc="); Serial.println(mqtt.state());
  }
}

// ========== SETUP ==========
void setup() {
  Serial.begin(115200);
  Wire.begin(21, 22);
  Wire.setClock(100000);

  // LCD Init
  lcd.init();
  lcd.backlight();
  lcd.setCursor(0, 0);
  lcd.print("SMART SNACK BOX");
  lcd.setCursor(0, 1);
  lcd.print("Inisialisasi...");

  // MLX Init
  mlx.begin();

  // MAX30102 Init
  if (!particleSensor.begin(Wire, I2C_SPEED_STANDARD)) {
    Serial.println("❌ MAX30102 tidak terdeteksi!");
  } else {
    particleSensor.setup();
    particleSensor.setPulseAmplitudeRed(0x0A);
    particleSensor.setPulseAmplitudeIR(0x1F);
    particleSensor.setPulseAmplitudeGreen(0);
  }

  // LoadCell Init
  scale.begin(HX711_DT_PIN, HX711_SCK_PIN);
  scale.set_scale(CALIBRATION_FACTOR);
  scale.tare();

  // Servo & Buzzer Init
  snackServo.attach(SERVO_PIN);
  snackServo.write(SERVO_CLOSED_ANGLE);
  pinMode(BUZZER_PIN, OUTPUT);
  digitalWrite(BUZZER_PIN, LOW);

  // MQTT Topics
  commandTopic = String("smartsnack/health/command/") + DEVICE_ID;
  resultTopic  = String("smartsnack/health/result/")  + DEVICE_ID;
  boxOpenTopic = String("smartsnack/box/open/")        + DEVICE_ID;

  // WiFi & MQTT Startup
  connectWifi();
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  mqtt.setCallback(mqttCallback);

  connectMqtt();

  delay(1500);
  lcd.clear();
}

// ========== MAIN LOOP ==========
void loop() {
  // 1. Maintain WiFi & MQTT
  if (WiFi.status() != WL_CONNECTED) {
    if (millis() - lastWifiRetryMs > 5000) {
      lastWifiRetryMs = millis();
      connectWifi();
    }
  } else if (!mqtt.connected()) {
    if (millis() - lastMqttReconnectMs > 3000) {
      lastMqttReconnectMs = millis();
      connectMqtt();
    }
  } else {
    mqtt.loop();
  }

  // 2. Continuous Background Sampling for MAX30102 (Heart Rate)
  long ir = particleSensor.getIR();
  if (ir < 50000) {
    beatAvg = 0; bpm = 0; rateSpot = 0;
    for (byte i = 0; i < RATE_SIZE; i++) rates[i] = 0;
  } else {
    if (checkForBeat(ir)) {
      long delta = millis() - lastBeat;
      lastBeat = millis();
      bpm = 60.0f / (delta / 1000.0f);
      if (bpm > 20 && bpm < 255) {
        rates[rateSpot++] = (byte)bpm;
        rateSpot %= RATE_SIZE;
        int totalRates = 0; byte validCount = 0;
        for (byte i = 0; i < RATE_SIZE; i++) {
          if (rates[i] > 0) { totalRates += rates[i]; validCount++; }
        }
        if (validCount > 0) beatAvg = totalRates / validCount;
      }
    }
  }

  // 3. Background Sampling Load Cell — Non-blocking, 1 sampel per loop (dengan Low-Pass Filter)
  if (scale.is_ready()) {
    float b = scale.get_units(1);
    if (b < 0.0f) b = 0.0f;
    
    if (b < WEIGHT_RAW_THRESHOLD) {
      // Reduksi berat secara smooth ke 0 agar stabil
      beratGlobal = (beratGlobal * 0.8f);
      if (beratGlobal < 1.0f) beratGlobal = 0.0f;
    } else {
      float corrected = (b - WEIGHT_OFFSET) / WEIGHT_SLOPE;
      if (corrected < 0.0f) corrected = 0.0f;
      // Exponential Moving Average (Low Pass Filter) agar angka timbangan tidak lompat-lompat
      if (beratGlobal == 0.0f) {
        beratGlobal = corrected; // Respon langsung saat pertama kali diinjak
      } else {
        beratGlobal = (beratGlobal * 0.7f) + (corrected * 0.3f);
      }
    }
  }

  // 4. Update LCD & Serial Periodic Print (Tiap 400ms)
  if (millis() - lastPrintMs > 400) {
    lastPrintMs = millis();
    float suhu = mlx.readObjectTempC() + BODY_TEMP_OFFSET;
    float jarak = readDistance();
    float berat = beratGlobal;
    // Hanya ukur tinggi jika ada orang di atas timbangan (berat > 15 kg)
    // Ini membuang pantulan palsu ultrasonik saat alat kosong
    float tinggi = (jarak > 0 && berat > 15.0f) ? SENSOR_HEIGHT_CM - jarak : 0.0f;

    // Pergantian Halaman LCD Setiap 2.5 Detik
    if (millis() - lastLcdPageMs > 2500) {
      lastLcdPageMs = millis();
      lcdPage = (lcdPage + 1) % 2;
      lcd.clear();
    }

    // Tampilan LCD
    if (servoIsOpen) {
      lcd.setCursor(0, 0);
      lcd.print("STATUS: TERBUKA ");
      lcd.setCursor(0, 1);
      lcd.print("SNACK DIBERIKAN!");
    } else {
      if (lcdPage == 0) {
        char line0[17], line1[17];
        snprintf(line0, sizeof(line0), "Suhu : %.1f C   ", suhu);
        if (ir < 50000) {
          snprintf(line1, sizeof(line1), "BPM  : Tempel   ");
        } else {
          snprintf(line1, sizeof(line1), "BPM  : %d bpm    ", beatAvg);
        }
        lcd.setCursor(0, 0); lcd.print(line0);
        lcd.setCursor(0, 1); lcd.print(line1);
      } else {
        char line0[17], line1[17];
        if (tinggi > 0) snprintf(line0, sizeof(line0), "Tinggi: %.1fcm  ", tinggi);
        else snprintf(line0, sizeof(line0), "Tinggi: -       ");
        snprintf(line1, sizeof(line1), "Berat : %.2fkg  ", berat);
        lcd.setCursor(0, 0); lcd.print(line0);
        lcd.setCursor(0, 1); lcd.print(line1);
      }
    }

    // --- SERIAL MONITOR PRINT ---
    Serial.println("===== SMART SNACK BOX =====");
    Serial.printf("Tinggi : %.1f cm\n", tinggi);
    Serial.printf("Berat  : %.2f kg (Raw: %.2f)\n", berat, scale.is_ready() ? scale.get_units(1) : -999.0f);
    Serial.printf("Suhu   : %.1f C\n", suhu);
    if (ir < 50000) Serial.println("BPM    : Tempelkan jari");
    else Serial.printf("BPM    : %d bpm\n", beatAvg);
    Serial.printf("Servo  : %s\n", servoIsOpen ? "TERBUKA" : "TERTUTUP");
    Serial.println();
  }

  // 5. Auto Close Servo
  closeServoIfNeeded();
}
