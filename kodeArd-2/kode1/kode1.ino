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
#include <Preferences.h>

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
Preferences       calibPrefs;   // Penyimpanan kalibrasi berat di flash (NVS), bertahan walau reset/reflash

// ===== KONFIGURASI WIFI & MQTT =====
const char* WIFI_SSID = "Ngrox";
const char* WIFI_PASS = "llllllll";

const char* MQTT_HOST = "54.144.6.206";
const int   MQTT_PORT = 1884;
const char* MQTT_USER = "";
const char* MQTT_PASS = "";
const char* DEVICE_ID = "esp32_health_01";

String commandTopic;
String resultTopic;
String boxOpenTopic;
String rawTopic;         // Topik data mentah real-time (grafik Flutter)

// ===== KALIBRASI SENSOR =====
const float SENSOR_HEIGHT_CM      = 174.0f;
const float BODY_TEMP_OFFSET      = 1.2f;
// Faktor kalibrasi HX711 (nilai dasar, jangan diubah)
const float CALIBRATION_FACTOR    = 7050.0f;

// ─── KALIBRASI 2 TITIK LINIER (PRESISI TINGGI) ────────────────────────
//  Rumus: actual_kg = (raw_val - weightOffset) / weightSlope
//
//  ✅ UPDATE 2 Agustus 2026 — VCC HX711 dipindah ke 3V3 ESP32 (sebelumnya
//  share rail Vin dgn servo). Ini mengubah tegangan eksitasi load cell
//  (5V -> 3.3V), yang otomatis mengubah gain HX711 -> SEMUA kalibrasi
//  sebelumnya (termasuk yang berbasis rail lama) sudah tidak berlaku.
//
//  Nilai default di bawah SUDAH di-estimasi ulang dari 1 titik data
//  sesi ini (BB aktual 64kg terbaca 48kg dgn konstanta lama), TAPI ini
//  cuma estimasi kasar (balik-hitung dari output lama, slope diasumsikan
//  belum berubah). JANGAN dipakai sebagai acuan akhir — WAJIB kalibrasi
//  ulang pakai prosedur di bawah sebelum dipakai serius. Karena rail
//  sekarang sudah lebih stabil (VCC dari ESP32, bukan share dgn servo),
//  hasil kalibrasi baru ini seharusnya jauh lebih tahan lama dari sesi
//  sebelumnya.
//
//  weightSlope & weightOffset adalah VARIABEL (bukan const) yang bisa
//  dikalibrasi ulang KAPAN SAJA lewat Serial Monitor — tanpa reflash —
//  dan otomatis TERSIMPAN PERMANEN di flash (NVS) via Preferences, jadi
//  tetap kepakai walau alat mati/nyala lagi.
//
//  CARA KALIBRASI (lakukan sekarang, sekali saja setelah ganti VCC 3V3):
//   1. Upload kode ini, buka Serial Monitor 115200, line ending pilih
//      "Both NL & CR" (atau "Newline").
//   2. Pastikan timbangan BENAR-BENAR KOSONG, ketik:  TARE   lalu Enter.
//   3. Naik ke timbangan dengan berat yang SUDAH DIKETAHUI PASTI (misal
//      badanmu sendiri, 64kg), diam beberapa detik sampai "Raw median"
//      di Serial stabil, lalu ketik:
//        CAL1:64        (ganti sesuai beratmu saat itu)
//   4. Turun, lalu naik lagi dengan beban KEDUA yang beda jauh (>5kg) dari
//      titik pertama — bisa orang lain, atau tambahan beban apapun yang
//      beratnya kamu tahu pasti — diam sampai stabil, lalu ketik:
//        CAL2:85        (ganti sesuai berat titik kedua)
//   5. Sistem otomatis hitung slope & offset baru, dan langsung disimpan
//      permanen. Selesai — tidak perlu upload ulang kode lagi.
float   weightSlope               = 3.5365f;   // fallback awal, akan ditimpa nilai tersimpan / hasil CAL
float   weightOffset              = -54.59f;   // estimasi kasar 1-titik (BB 64kg -> lihat catatan di atas), akan ditimpa nilai tersimpan / hasil CAL
//  Jika nilai raw di bawah threshold ini, timbangan dianggap kosong
const float WEIGHT_RAW_THRESHOLD  = 15.0f;

// Variabel sementara untuk proses kalibrasi 2 titik via Serial
float   calPoint1Raw    = 0.0f;
float   calPoint1Weight = 0.0f;
bool    calPoint1Set    = false;

const int   SERVO_CLOSED_ANGLE    = 0;
const int   SERVO_OPEN_ANGLE      = 35;
const unsigned long SERVO_AUTO_CLOSE_MS = 10000; // 10 Detik

// ===== STATE VARIABLES =====
unsigned long lastMqttReconnectMs = 0;
unsigned long lastWifiRetryMs     = 0;
bool          servoIsOpen         = false;
unsigned long servoOpenedAtMs     = 0;
float         beratGlobal         = 0.0f;
float         rawGlobal           = -999.0f;  // Cache raw HX711 (setelah median filter) dari background sampling
bool          isMeasuring         = false;  // Cegah re-entrancy MQTT callback
bool          wasLoaded           = false;  // Lacak transisi kosong -> ada beban, buat fast-settle median filter

// ─── MEDIAN FILTER UNTUK RAW HX711 ─────────────────────────────────────
// Median filter membuang outlier ekstrem SEBELUM masuk ke EMA, jadi satu
// sampel "nyasar" tidak langsung menarik hasil akhir.
const int RAW_HISTORY_SIZE = 5;
float rawHistory[RAW_HISTORY_SIZE];
int   rawHistoryIdx = 0;
int   rawHistoryCount = 0;

float pushRawAndGetMedian(float newRaw) {
  rawHistory[rawHistoryIdx] = newRaw;
  rawHistoryIdx = (rawHistoryIdx + 1) % RAW_HISTORY_SIZE;
  if (rawHistoryCount < RAW_HISTORY_SIZE) rawHistoryCount++;

  // Copy & sort (insertion sort, cukup untuk array sekecil ini)
  float sorted[RAW_HISTORY_SIZE];
  for (int i = 0; i < rawHistoryCount; i++) sorted[i] = rawHistory[i];
  for (int i = 1; i < rawHistoryCount; i++) {
    float key = sorted[i];
    int j = i - 1;
    while (j >= 0 && sorted[j] > key) {
      sorted[j + 1] = sorted[j];
      j--;
    }
    sorted[j + 1] = key;
  }
  return sorted[rawHistoryCount / 2]; // nilai tengah = median
}

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

// Konversi raw HX711 (setelah median filter) -> kg, pakai kalibrasi 2-titik.
// Dipisah jadi fungsi sendiri supaya dipakai bareng oleh loop() (background,
// untuk LCD) dan measureWeightKg() (foreground, untuk hasil ke app) tanpa
// duplikasi rumus.
float rawToKg(float rawMedian) {
  float b = rawMedian;
  if (b < 0.0f) b = 0.0f;
  if (b < WEIGHT_RAW_THRESHOLD) return 0.0f;
  float corrected = (b - weightOffset) / weightSlope;
  if (corrected < 0.0f) corrected = 0.0f;
  return corrected;
}

// Baca 1 "sampel efektif" dari HX711 (sudah lewat median filter) dan update
// rawGlobal. Dipakai bareng oleh loop() (background, LCD) dan
// measureWeightKg() (foreground, hasil ke app) supaya perilaku fast-settle
// di bawah konsisten di keduanya, tanpa duplikasi logic.
//
// FAST-SETTLE: median filter (RAW_HISTORY_SIZE=5) normalnya butuh 5 iterasi
// buat "melupakan" histori lama (dekat nol) begitu ada beban baru naik ke
// timbangan -> itu sebabnya sebelumnya angka di LCD/serial kelihatan naik
// pelan-pelan (3 -> 6 -> 11 -> 14 ...) padahal beban sudah ada dari awal.
// Begitu kedeteksi transisi kosong->berisi, kita langsung "banjiri" buffer
// dengan beberapa bacaan cepat berturut-turut supaya median langsung
// merepresentasikan beban saat ini, bukan campuran data lama+baru.
float sampleRawOnce() {
  float bRaw = scale.get_units(1);
  bool isLoadedNow = (bRaw >= WEIGHT_RAW_THRESHOLD);

  if (isLoadedNow && !wasLoaded) {
    for (int i = 0; i < RAW_HISTORY_SIZE; i++) {
      pushRawAndGetMedian(scale.get_units(1));
      delay(5);
    }
    bRaw = scale.get_units(1);
  }
  wasLoaded = isLoadedNow;

  float b = pushRawAndGetMedian(bRaw);
  rawGlobal = b;
  return b;
}

// ========== KALIBRASI VIA SERIAL MONITOR ==========
// Non-blocking: dipanggil tiap loop(), cuma proses kalau ada input baru.
// Perintah: TARE | CAL1:<berat_kg> | CAL2:<berat_kg>
void handleSerialCalibration() {
  if (!Serial.available()) return;
  String cmd = Serial.readStringUntil('\n');
  cmd.trim();
  if (cmd.length() == 0) return;

  if (cmd.equalsIgnoreCase("TARE")) {
    Serial.println("[KALIBRASI] Pastikan timbangan KOSONG TOTAL sekarang...");
    delay(1000);
    scale.tare(20);
    rawHistoryCount = 0; rawHistoryIdx = 0;  // reset median filter biar gak kebawa data lama
    beratGlobal = 0.0f;
    Serial.println("[KALIBRASI] Tare selesai. Sekarang naik ke timbangan dgn berat diketahui, lalu kirim CAL1:<berat>");
  }
  else if (cmd.startsWith("CAL1:")) {
    float w1 = cmd.substring(5).toFloat();
    if (w1 <= 0) { Serial.println("[KALIBRASI] GAGAL: berat tidak valid."); return; }
    calPoint1Raw    = rawGlobal;
    calPoint1Weight = w1;
    calPoint1Set    = true;
    Serial.printf("[KALIBRASI] Titik 1 disimpan: raw=%.2f @ %.2f kg\n", calPoint1Raw, w1);
    Serial.println("[KALIBRASI] Sekarang ganti beban (beda >5kg), tunggu stabil, lalu kirim CAL2:<berat>");
  }
  else if (cmd.startsWith("CAL2:")) {
    if (!calPoint1Set) {
      Serial.println("[KALIBRASI] GAGAL: kirim CAL1:<berat> dulu sebelum CAL2.");
      return;
    }
    float w2 = cmd.substring(5).toFloat();
    if (w2 <= 0) { Serial.println("[KALIBRASI] GAGAL: berat tidak valid."); return; }
    if (fabs(w2 - calPoint1Weight) < 5.0f) {
      Serial.println("[KALIBRASI] GAGAL: berat titik 2 harus beda >5kg dari titik 1 (biar akurat).");
      return;
    }
    float raw2 = rawGlobal;
    float newSlope  = (raw2 - calPoint1Raw) / (w2 - calPoint1Weight);
    float newOffset = calPoint1Raw - (newSlope * calPoint1Weight);

    weightSlope  = newSlope;
    weightOffset = newOffset;
    calibPrefs.putFloat("slope", weightSlope);
    calibPrefs.putFloat("offset", weightOffset);
    calPoint1Set = false;

    Serial.println("[KALIBRASI] ===== SELESAI & TERSIMPAN PERMANEN =====");
    Serial.printf("[KALIBRASI] weightSlope=%.4f  weightOffset=%.4f\n", weightSlope, weightOffset);
  }
  else {
    Serial.println("[KALIBRASI] Perintah tidak dikenal. Pakai: TARE | CAL1:<berat> | CAL2:<berat>");
  }
}

// ========== MEASUREMENT FUNCTIONS FOR MQTT / FLUTTER ==========

float measureHeartRateBpm(String& errorCode, const String& checkId) {
  Serial.println(">>> Pengukuran Detak Jantung via Aplikasi <<<");
  unsigned long startTime = millis();
  int validBeats = 0;
  unsigned long lastRawPublish = 0;

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

    // Publish data mentah ke rawTopic setiap 2 detik (untuk grafik real-time Flutter)
    if (millis() - lastRawPublish >= 2000) {
      lastRawPublish = millis();
      int totalRates = 0, validCount = 0;
      for (byte i = 0; i < RATE_SIZE; i++) {
        if (rates[i] > 0) {
          totalRates += rates[i];
          validCount++;
        }
      }
      float liveBpm = (validCount > 0) ? ((float)totalRates / validCount) : 0.0f;
      bool fingerOn = (ir > 50000);
      String rawPayload = "{\"action\":\"heart_rate_raw\",\"check_id\":" + checkId + ",\"bpm\":" + String(liveBpm, 1) + ",\"ir\":" + String(ir) + ",\"finger_on\":" + (fingerOn ? "true" : "false") + ",\"device_id\":\"" + DEVICE_ID + "\"}";
      if (mqtt.connected()) {
        mqtt.publish(rawTopic.c_str(), rawPayload.c_str());
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

float measureBodyTemperatureC(String& errorCode, const String& checkId) {
  Serial.println(">>> Pengukuran Suhu Tubuh via Aplikasi <<<");
  float totalTemp = 0.0f;
  int count = 0;
  // Pengambilan sampel selama 2 detik (20 x 100ms)
  for (int i = 0; i < 20; i++) {
    if (mqtt.connected()) mqtt.loop();
    float t = mlx.readObjectTempC();
    if (!isnan(t) && t > 10.0f && t < 50.0f) {
      totalTemp += t;
      count++;
      float calibratedT = t + BODY_TEMP_OFFSET;
      String rawPayload = "{\"action\":\"body_temp_raw\",\"check_id\":" + checkId + ",\"temp\":" + String(calibratedT, 2) + ",\"device_id\":\"" + DEVICE_ID + "\"}";
      if (mqtt.connected()) {
        mqtt.publish(rawTopic.c_str(), rawPayload.c_str());
      }
    }
    delay(100);
  }

  if (count == 0) {
    // Fallback: coba baca sekali lagi
    float t = mlx.readObjectTempC();
    if (!isnan(t) && t > 0.0f) {
      totalTemp = t;
      count = 1;
    } else {
      errorCode = "sensor_unavailable";
      return 0.0f;
    }
  }

  float avgTemp = (totalTemp / count) + BODY_TEMP_OFFSET;
  Serial.print("Hasil Suhu: "); Serial.println(avgTemp, 1);
  return avgTemp;
}

float measureWeightKg(String& errorCode) {
  Serial.println(">>> Pengukuran Berat Badan via Aplikasi <<<");

  // Ambil sampling cepat (100ms) dari sensor HX711 agar respon realtime & tidak delay
  float localEma = beratGlobal;
  unsigned long startTime = millis();

  while (millis() - startTime < 100) {
    if (mqtt.connected()) mqtt.loop();

    if (scale.is_ready()) {
      float b = sampleRawOnce();

      if (b < WEIGHT_RAW_THRESHOLD) {
        localEma *= 0.7f;
        if (localEma < 0.5f) localEma = 0.0f;
      } else {
        float corrected = rawToKg(b);
        localEma = (localEma * 0.4f) + (corrected * 0.6f);
      }
    }
    delay(10);
  }

  if (localEma < 0.5f) {
    localEma = 0.0f; // Beban kosong = 0.0 kg (data valid, BUKAN error)
  }

  beratGlobal = localEma;  // sinkronkan balik ke global
  Serial.printf("Aktual: %.2f kg\n", localEma);
  return localEma;
}

float measureHeightCm(String& errorCode) {
  Serial.println(">>> Pengukuran Tinggi Badan via Aplikasi <<<");
  float total = 0.0f;
  int validCount = 0;

  // Ambil 5 sampel ultrasonik untuk memastikan sinyal stabil
  for (int i = 0; i < 5; i++) {
    float d = readDistance();
    if (d > 0) {
      total += d;
      validCount++;
    }
    delay(30);
  }

  if (validCount == 0) {
    errorCode = "signal_invalid";
    return 0.0f;
  }

  float dist = total / validCount;
  float tinggi = SENSOR_HEIGHT_CM - dist;
  if (tinggi < 0) tinggi = 0.0f;
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
    float bpmVal = measureHeartRateBpm(errorCode, checkId);
    if (errorCode.length() > 0) publishError(checkId, action, errorCode);
    else publishHeartRate(checkId, bpmVal);
  } else if (action == "body_temperature") {
    float tempVal = measureBodyTemperatureC(errorCode, checkId);
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
  Wire.setClock(50000); // 50kHz stabil untuk MLX
  Wire.setTimeOut(100); // Timeout 100ms cegah bus I2C hang

  // LCD Init
  lcd.init();
  lcd.backlight();
  lcd.setCursor(0, 0);
  lcd.print("SMART SNACK BOX");
  lcd.setCursor(0, 1);
  lcd.print("Inisialisasi...");

  // MLX Init
  mlx.begin();
  delay(100);

  // MAX30102 Init dengan Retry 5 Kali & Speed Switching
  bool maxReady = false;
  for (int retry = 0; retry < 5; retry++) {
    Wire.setClock(400000);
    if (particleSensor.begin(Wire, I2C_SPEED_FAST)) {
      maxReady = true;
      break;
    }
    delay(50);
  }

  if (!maxReady) {
    Wire.setClock(100000);
    if (particleSensor.begin(Wire, I2C_SPEED_STANDARD)) {
      maxReady = true;
    }
  }

  if (maxReady) {
    particleSensor.setup();
    particleSensor.setPulseAmplitudeRed(0x24); // Nyalakan Red LED lebih terang
    particleSensor.setPulseAmplitudeIR(0x24);  // Nyalakan IR LED
    particleSensor.setPulseAmplitudeGreen(0);
    Serial.println("✅ MAX30102 Berhasil Diinisialisasi!");
  } else {
    Serial.println("❌ MAX30102 tidak terdeteksi!");
  }

  Wire.setClock(100000); // Kembalikan ke 100kHz standard untuk operasional normal

  // LoadCell Init
  scale.begin(HX711_DT_PIN, HX711_SCK_PIN);
  scale.set_scale(CALIBRATION_FACTOR);

  // FIX: tunggu HX711 benar-benar siap sebelum tare, lalu tare beberapa kali
  // dan pastikan timbangan kosong. Tare yang dilakukan saat chip belum stabil
  // (langsung setelah power-on) adalah salah satu penyebab umum baseline drift.
  Serial.println("[HX711] Menunggu sensor siap untuk tare...");
  unsigned long tareWaitStart = millis();
  while (!scale.is_ready() && (millis() - tareWaitStart) < 5000) {
    delay(50);
  }
  if (scale.is_ready()) {
    delay(500); // beri waktu pembacaan stabil dulu
    scale.tare(20); // rata-rata 20 pembacaan untuk tare yang lebih presisi
    Serial.println("[HX711] Tare selesai.");
  } else {
    Serial.println("[HX711] WARNING: sensor tidak merespons, tare dilewati!");
  }

  // Muat kalibrasi berat yang tersimpan permanen (hasil CAL1/CAL2 sebelumnya).
  // Kalau belum pernah dikalibrasi lewat Serial, tetap pakai nilai default
  // fallback (estimasi kasar) di atas.
  calibPrefs.begin("scalecal", false);
  weightSlope  = calibPrefs.getFloat("slope", weightSlope);
  weightOffset = calibPrefs.getFloat("offset", weightOffset);
  Serial.printf("[KALIBRASI] Dimuat: weightSlope=%.4f weightOffset=%.4f\n", weightSlope, weightOffset);
  Serial.println("[KALIBRASI] Ketik TARE / CAL1:<berat> / CAL2:<berat> di Serial Monitor kapan saja untuk kalibrasi ulang.");

  // Servo & Buzzer Init
  snackServo.attach(SERVO_PIN);
  snackServo.write(SERVO_CLOSED_ANGLE);
  pinMode(BUZZER_PIN, OUTPUT);
  digitalWrite(BUZZER_PIN, LOW);

  // MQTT Topics
  commandTopic = String("smartsnack/health/command/") + DEVICE_ID;
  resultTopic  = String("smartsnack/health/result/")  + DEVICE_ID;
  boxOpenTopic = String("smartsnack/box/open/")        + DEVICE_ID;
  rawTopic     = String("smartsnack/health/raw/")     + DEVICE_ID;

  // WiFi & MQTT Startup
  connectWifi();
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  mqtt.setCallback(mqttCallback);
  mqtt.setBufferSize(512);    // Perbesar buffer agar JSON payload tidak terpotong
  mqtt.setKeepAlive(90);      // Keepalive 90 detik, cukup untuk pengukuran detak jantung

  connectMqtt();

  delay(1500);
  lcd.clear();
}

// ========== MAIN LOOP ==========
void loop() {
  // 0. Cek perintah kalibrasi dari Serial Monitor (TARE / CAL1:x / CAL2:x)
  handleSerialCalibration();

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

  // 3. Background Sampling Load Cell — Non-blocking, dengan median filter +
  //    fast-settle (lihat sampleRawOnce()) + EMA (Low-Pass Filter). Ini
  //    dipakai untuk tampilan LCD/serial saja; hasil yang dikirim ke app
  //    dihitung terpisah di measureWeightKg() (lihat catatan re-entrancy
  //    di sana), tapi keduanya pakai sampleRawOnce() yang sama.
  if (scale.is_ready()) {
    float b = sampleRawOnce();

    if (b < WEIGHT_RAW_THRESHOLD) {
      // Reduksi berat secara smooth ke 0 agar stabil
      beratGlobal = (beratGlobal * 0.8f);
      if (beratGlobal < 1.0f) beratGlobal = 0.0f;
    } else {
      float corrected = rawToKg(b);
      // Exponential Moving Average (Low Pass Filter)
      if (beratGlobal == 0.0f) {
        beratGlobal = corrected; // Respon langsung saat pertama kali diinjak
      } else {
        beratGlobal = (beratGlobal * 0.9f) + (corrected * 0.1f);
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
    // Pakai rawGlobal (hasil median filter di bagian 3), bukan raw mentah
    Serial.println("===== SMART SNACK BOX =====");
    Serial.printf("Tinggi : %.1f cm\n", tinggi);
    Serial.printf("Berat  : %.2f kg (Raw median: %.2f)\n", berat, rawGlobal);
    Serial.printf("Suhu   : %.1f C\n", suhu);
    if (ir < 50000) Serial.println("BPM    : Tempelkan jari");
    else Serial.printf("BPM    : %d bpm\n", beatAvg);
    Serial.printf("Servo  : %s\n", servoIsOpen ? "TERBUKA" : "TERTUTUP");
    Serial.println();
  }

  // 5. Auto Close Servo
  closeServoIfNeeded();
}
