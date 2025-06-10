/*************************************************************************
 *  ESP32-S3 – ThingsBoard leaf node (ESP-NOW)
 *  Features: DHT20 telemetry, RPC-driven servo, OTA by HTTP
 *************************************************************************/
#include <WiFi.h>
#include <esp_wifi.h>
#include <esp_now.h>

#include <WiFiClientSecure.h>         // ← TLS socket (must be here)
#include <HTTPClient.h>               // makes HTTPS requests

#include <ArduinoJson.h>
#include <Wire.h>
#include "DHT20.h"
#include <ESP32Servo.h>
#include <Update.h>

//========= USER CONFIG ===================================================
constexpr char WIFI_SSID[]       = "RD-SEAI_2.4G";
constexpr char WIFI_PASSWORD[]   = "";

/* MAC of your gateway’s STA interface (AA:BB:CC:DD:EE:FF)  */
constexpr uint8_t GATEWAY_MAC[6] = { 0xCC,0xBA,0x97,0x08,0xD1,0xA8 };

constexpr uint8_t ESPNOW_CHANNEL = 11;     // must match Wi-Fi channel
constexpr uint16_t TELEMETRY_MS  = 10000;

constexpr uint8_t  SERVO_PIN     = 5;     // any PWM-capable pin
constexpr uint8_t  SDA_PIN       = 11;
constexpr uint8_t  SCL_PIN       = 12;
//=========================================================================

//----- Packet format (same as gateway) -----------------------------------
enum class PacketType : uint8_t { TELEMETRY, ATTRIBUTE, RPC_REQ, RPC_RESP };

struct __attribute__((packed)) GwPacket {
  PacketType type;
  uint8_t    reqId;                  // RPC only
  char       json[230];              // payload ≤ 230 B
};

//----- Globals -----------------------------------------------------------
static DHT20       dht20;
static Servo       servo;
static uint32_t    lastTelemetry = 0;
static uint8_t     lastRpcId     = 0;     // to echo back

// Helper – MAC string
String macToStr(const uint8_t *mac) {
  char buf[18];
  sprintf(buf,"%02X:%02X:%02X:%02X:%02X:%02X",
          mac[0],mac[1],mac[2],mac[3],mac[4],mac[5]);
  return String(buf);
}

//------------- ESPNOW helpers -------------------------------------------
bool sendPacket(const GwPacket &pkt) {
  esp_err_t ok = esp_now_send(GATEWAY_MAC,(uint8_t*)&pkt,sizeof(pkt));
  return ok == ESP_OK;
}

//------------- OTA (HTTP over Wi-Fi) ------------------------------------
bool doHttpOta(const String &url) {
  Serial.printf("OTA: download %s\n", url.c_str());

  WiFiClientSecure net;                  // ➋ TLS-capable client
  net.setInsecure();                     //    (skip CA check; add root
                                         //     cert here if you prefer)

  HTTPClient http;
  http.setFollowRedirects(HTTPC_STRICT_FOLLOW_REDIRECTS);   // ➌ Dropbox = 302
  if (!http.begin(net, url)) {           // ➍ use secure client
    Serial.println("HTTP begin failed");
    return false;
  }

  int code = http.GET();
  if (code != HTTP_CODE_OK) {
    Serial.printf("HTTP GET failed: %d\n", code);
    return false;
  }

  int len = http.getSize();              // may be -1 (chunked)
  WiFiClient &stream = http.getStream();

  if (!Update.begin(len > 0 ? len : UPDATE_SIZE_UNKNOWN)) { // ➎ flexible
    Serial.println("Update.begin failed");
    return false;
  }

  uint8_t buf[2048];
  size_t written = 0;
  while (http.connected() && (len < 0 || written < (size_t)len)) {
    size_t n = stream.available();
    if (n) {
      n = stream.readBytes(buf, std::min(n, sizeof(buf)));
      if (Update.write(buf, n) != n) {
        Serial.println("Update.write failed");
        return false;
      }
      written += n;
    }
    delay(1);
  }

  if (!Update.end()) {
    Serial.printf("Update error: %s\n", Update.errorString());
    return false;
  }
  Serial.println("OTA successful – rebooting");
  delay(500);
  ESP.restart();
  return true;           // never reached
}
//------------- ESPNOW receive callback ----------------------------------
void onEspNowRecv(const esp_now_recv_info_t  *info,
                  const uint8_t            *data,
                  int len) {
  Serial.println("ESPNOW Recv: Got a package");
  if (len < (int)sizeof(PacketType)) return;
  PacketType type = *(PacketType*)data;
  const GwPacket *pkt = (const GwPacket*)data;
  Serial.printf("len=%d firstByte=%02X\n", len, (uint8_t)pkt->json[0]);
  Serial.printf("Rx JSON: %s\n", pkt->json);
  if (type == PacketType::ATTRIBUTE) {     // NEW branch
      DynamicJsonDocument att(256);
      deserializeJson(att, pkt->json);

      if (att.containsKey("fw_url")) {
          String url  = att["fw_url"].as<String>();
          String ver  = att["fw_version"] | "";
          String title= att["fw_title"]  | "";

          Serial.printf("FW update ► %s  (%s)\n", title.c_str(), url.c_str());

          bool ok = doHttpOta(url);                 // your existing HTTP-OTA
          // send back minimal progress attribute
          DynamicJsonDocument resp(64);
          resp["fw_state"] = ok ? "UPDATED" : "FAILED";

          GwPacket a{};
          a.type = PacketType::ATTRIBUTE;           // upstream attr update
          serializeJson(resp, a.json, sizeof(a.json));
          sendPacket(a);
      }
  } else {
    if (type != PacketType::RPC_REQ) return;          // ignore everything else
    DynamicJsonDocument doc(512);
    if (deserializeJson(doc, pkt->json) != DeserializationError::Ok) return;
    DeserializationError err = deserializeJson(doc, pkt->json);
    Serial.println(err.f_str());
    String method = doc["method"] | "";
    Serial.println(doc["method"].as<const char*>());
    lastRpcId     = doc["id"] | 0;

    bool success  = false;

    int ang = 90 - servo.read();
    servo.write(ang);
    success = true;                    // generic success response later
  }
}

//==================== SETUP =============================================
void setup() {
  Serial.begin(115200);
  delay(300);

  /* Wi-Fi (needed for ESP-NOW + OTA) */
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500); Serial.print('.');
  }
  Serial.printf("\nWi-Fi OK  IP=%s  ch=%d\n", WiFi.localIP().toString().c_str(), WiFi.channel());

  /* ESP-NOW */
  if (esp_now_init() != ESP_OK) {
    Serial.println("ESP-NOW init failed!"); ESP.restart();
  }
  esp_now_register_recv_cb(onEspNowRecv);
  esp_wifi_set_channel(ESPNOW_CHANNEL, WIFI_SECOND_CHAN_NONE);

  /* Register gateway as peer (unicast) */
  esp_now_peer_info_t peer{};
  memcpy(peer.peer_addr, GATEWAY_MAC, 6);
  peer.channel = ESPNOW_CHANNEL;
  peer.ifidx   = WIFI_IF_STA;
  peer.encrypt = false;
  esp_now_add_peer(&peer);

  /* DHT20 + Servo */
  Wire.begin(SDA_PIN, SCL_PIN);
  dht20.begin();

  servo.setPeriodHertz(50);   // SG90 class
  servo.attach(SERVO_PIN);
  servo.write(90);            // neutral

  Serial.println("Node ready.");
}

//==================== LOOP ==============================================
void loop() {

  /* Periodic telemetry */
  if (millis() - lastTelemetry >= TELEMETRY_MS) {
    lastTelemetry = millis();

    dht20.read();
    float t = dht20.getTemperature();
    float h = dht20.getHumidity();

    DynamicJsonDocument doc(128);
    doc["mac"]        = WiFi.macAddress();
    if (!isnan(t)) doc["temperature"] = t;
    if (!isnan(h)) doc["humidity"]    = h;
    doc["servo"]      = servo.read();

    char jsonBuf[128];
    size_t n = serializeJson(doc, jsonBuf);

    GwPacket pkt{};
    pkt.type = PacketType::TELEMETRY;
    memcpy(pkt.json, jsonBuf, n+1);

    sendPacket(pkt);

    Serial.print("Temperature: ");
    Serial.print(t);
    Serial.print(" °C, Humidity: ");
    Serial.print(h);
    Serial.println(" %");
  }

  delay(10);   // idle
}
