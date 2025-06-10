/*************************************************************************
 *  ESP32-S3 ThingsBoard Gateway – ESP-NOW ⇄ MQTT
 *************************************************************************/
#include <WiFi.h>
#include <esp_wifi.h>
#include <esp_now.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <set.h>

// ========================= USER CONFIG =================================
constexpr char WIFI_SSID[]       = "RD-SEAI_2.4G";
constexpr char WIFI_PASSWORD[]   = "";
constexpr char TB_TOKEN[]        = "omzkj7kspjdm6ar3qe2z";      // gateway device access token
constexpr char TB_HOST[]         = "app.coreiot.io";
constexpr uint16_t TB_PORT       = 1883;

constexpr uint8_t  ESPNOW_CHANNEL = 11;   // MUST match home-router channel or use WiFi.setChannel
constexpr size_t   JSON_CAPACITY  = 512; // enough for telemetry + wrapper
// =======================================================================

// ---------- MQTT --------------------------------------------------------
WiFiClient   wifi;
PubSubClient mqtt(wifi);

// ---------- ESP-NOW packet format --------------------------------------
enum class PacketType : uint8_t { TELEMETRY, ATTRIBUTE, RPC_REQ, RPC_RESP };

struct __attribute__((packed)) NodePacket {
  PacketType type;
  uint8_t    reqId;         // 0 for telemetry/attr
  char       json[230];
};

struct __attribute__((packed)) GwPacket {
  uint8_t    mac[6];           // NEW – filled by ISR, used by MQTT task
  PacketType type;
  uint8_t    reqId;            // only for RPC
  char       json[230];        // payload (<= 230 bytes for ESPNOW)
};

// ---------- FreeRTOS queues --------------------------------------------
QueueHandle_t qFromNodes;       // packets received from nodes
QueueHandle_t qToNodes;         // packets to be forwarded to nodes

// Helper – MAC to string  AA:BB:CC:DD:EE:FF
String macToStr(const uint8_t *mac) {
  char buf[18];
  sprintf(buf, "%02X:%02X:%02X:%02X:%02X:%02X",
          mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  return String(buf);
}

// ====================== ESP-NOW CALLBACKS ===============================
void onEspNowRecv(const esp_now_recv_info_t *info,
                  const uint8_t            *data,
                  int                       len) {
  if (len < sizeof(GwPacket) - 6) return;              // sanity check

  GwPacket pkt;
  memcpy(pkt.mac, info->src_addr, 6);                  // copy MAC
  memcpy(&pkt.type, data, len);                        // copy rest of frame

  Serial.println("ESPNOW Recv: Got a package");

  xQueueSendFromISR(qFromNodes, &pkt, nullptr);
}

void onEspNowSend(const uint8_t *mac, esp_now_send_status_t status) {
  Serial.printf("Send to %s : %s\n",
                macToStr(mac).c_str(),
                status == ESP_NOW_SEND_SUCCESS ? "OK" : "FAIL");
}

// ===================== WIFI + MQTT HELPERS =============================
void connectWiFi() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print('.');
  }
  Serial.printf("\nWiFi ✓  IP=%s  RSSI=%d dBm  ch=%d\n",
                WiFi.localIP().toString().c_str(), WiFi.RSSI(), WiFi.channel());
}

bool strToMac(const String &src, uint8_t mac[6]) {
  unsigned int b[6];
  if (sscanf(src.c_str(),
             "%02x:%02x:%02x:%02x:%02x:%02x",
             &b[0], &b[1], &b[2], &b[3], &b[4], &b[5]) != 6) {
    return false;
  }
  for (int i = 0; i < 6; ++i) mac[i] = (uint8_t)b[i];
  return true;
}

bool ensurePeer(const uint8_t mac[6]) {
  esp_now_peer_info_t info{};
  if (esp_now_is_peer_exist(mac)) return true;  // already there

  memcpy(info.peer_addr, mac, 6);
  info.channel = ESPNOW_CHANNEL;               // same as Wi-Fi
  info.ifidx   = WIFI_IF_STA;
  info.encrypt = false;

  esp_err_t err = esp_now_add_peer(&info);
  if (err != ESP_OK) {
    Serial.printf("Cannot add peer %s  err=%d\n", macToStr(mac).c_str(), err);
    return false;
  }
  Serial.printf("Peer added: %s\n", macToStr(mac).c_str());
  return true;
}

void mqttCallback(char *topic, byte *payload, unsigned int length) {
    // Only subscribed to v1/gateway/rpc
    if (strcmp(topic, "v1/gateway/attributes") == 0) {
    Serial.printf("\n--- RAW (%u B) ---\n%.*s\n---------------\n",
              length, length, payload);          // dump entire JSON

    StaticJsonDocument<2048> doc;                     // big enough
    DeserializationError je = deserializeJson(doc, payload, length);
    if (je) { Serial.println(je.f_str()); return; }

    String macStr = doc["device"] | "";
    uint8_t mac[6];
    if (!strToMac(macStr, mac)) return;

    /* ── pick the correct source object ─────────────────────────── */
    JsonObject src =
        doc["data"]["shared"].is<JsonObject>()           // ➊ preferred
        ? doc["data"]["shared"].as<JsonObject>()         //    (FW assign)
        : doc["data"].as<JsonObject>();                  // ➋ fallback (others)

    /* ── copy only the fw_* pairs ──────────────────────────────── */
    DynamicJsonDocument slim(512);
    for (JsonPair kv : src) {
        const char *k = kv.key().c_str();
        if (strncmp(k, "fw_", 3) == 0) slim[k] = kv.value();
    }
    if (slim.isNull()) {                                // nothing copied →
        Serial.println("ATTR contains no fw_* keys");   //   don't send
        return;
    }

    NodePacket pkt;
    pkt.type  = PacketType::ATTRIBUTE;
    pkt.reqId = 0;

    /* always clear – avoids stale '\0' at pos0  */
    memset(pkt.json, 0, sizeof(pkt.json));               // ★ NEW

    size_t n = serializeJson(slim, pkt.json, sizeof(pkt.json) - 1);
    pkt.json[n] = '\0';                       // ★ add this
    Serial.printf("packed %u B  '%.*s'\n", n, (int)n, pkt.json);
    Serial.printf("→ node ATTR: %s\n", pkt.json);       // should NOT be null

    if (ensurePeer(mac)) esp_now_send(mac,
                                      reinterpret_cast<uint8_t*>(&pkt),
                                      sizeof(pkt));
        return;
  } else {
    Serial.println("RPC invoked");
    DynamicJsonDocument doc(JSON_CAPACITY);
    DeserializationError err = deserializeJson(doc, payload, length);
    if (err) return;
    Serial.println(length);
    NodePacket pkt;
    pkt.type  = PacketType::RPC_REQ;
    pkt.reqId = doc["id"] | 0;
    size_t n = serializeJson(doc, pkt.json, sizeof(pkt.json));
    if (n == sizeof(pkt.json)) {             // buffer exactly full
      // keep the last byte for '\0' so the node can parse
      pkt.json[sizeof(pkt.json) - 1] = '\0';
    }
    Serial.printf("→ node: %s\n", pkt.json);

    // Forward to node based on MAC in message
    String macStr = doc["device"] | "";
    Serial.println(macStr);
    uint8_t mac[6];
    if (!strToMac(macStr, mac)) {
      Serial.printf("Bad MAC in RPC: %s\n", macStr.c_str());
      return;                                 // drop message
    }

    if (ensurePeer(mac)) {
      esp_err_t err = esp_now_send(mac, (uint8_t *)&pkt, sizeof(pkt));
      if (err != ESP_OK) {
        Serial.printf("ESP-NOW send failed (%d)\n", err);
      }
    }
  }
}

void ensureMqtt() {
  while (!mqtt.connected()) {
    Serial.print("MQTT …");
    if (mqtt.connect("esp32S3_gateway", TB_TOKEN, nullptr)) {
      Serial.println("connected");
      mqtt.subscribe("v1/gateway/rpc");
      mqtt.subscribe("v1/gateway/attributes");
    } else {
      Serial.printf("failed rc=%d\n", mqtt.state());
      delay(1000);
    }
  }
}

// ======================== GATEWAY LOGIC =================================
void gatewayPublish(const String &deviceMac, PacketType type,
                    const char* jsonPayload, uint8_t reqId = 0) {

  DynamicJsonDocument doc(JSON_CAPACITY);

  switch (type) {
    case PacketType::TELEMETRY:
      { // {"MAC":[{payload}]}
        JsonArray arr = doc.createNestedArray(deviceMac);
        DynamicJsonDocument tmp(JSON_CAPACITY/2);
        deserializeJson(tmp, jsonPayload);
        arr.add(tmp.as<JsonObject>());
        char buf[JSON_CAPACITY];
        size_t n = serializeJson(doc, buf);
        mqtt.publish("v1/gateway/telemetry", buf, n);
      }
      break;

    case PacketType::ATTRIBUTE:
      { // {"MAC":{payload}}
        deserializeJson(doc, "{}");
        DynamicJsonDocument tmp(JSON_CAPACITY/2);
        deserializeJson(tmp, jsonPayload);
        doc[deviceMac] = tmp.as<JsonObject>();
        char buf[JSON_CAPACITY];
        size_t n = serializeJson(doc, buf);
        mqtt.publish("v1/gateway/attributes", buf, n);
      }
      break;

    case PacketType::RPC_RESP:
      { // {"device":"MAC","id":reqId,"data":{payload}}
        doc["device"] = deviceMac;
        doc["id"]     = reqId;
        DynamicJsonDocument tmp(JSON_CAPACITY/2);
        deserializeJson(tmp, jsonPayload);
        doc["data"] = tmp.as<JsonObject>();
        char buf[JSON_CAPACITY];
        size_t n = serializeJson(doc, buf);
        mqtt.publish("v1/gateway/rpc", buf, n);
      }
      break;

    default: break;  // RPC_REQ never published upstream
  }
}

// ========================= TASKS ========================================
void taskFromNodes(void *) {
  GwPacket pkt;
  while (true) {
    if (xQueueReceive(qFromNodes, &pkt, portMAX_DELAY) == pdTRUE) {
      String fromMac = macToStr(pkt.mac);
    }
  }
}

// ============================= SETUP ====================================
void setup() {
  Serial.begin(115200);
  delay(500);

  connectWiFi();

  // Init ESP-NOW
  if (esp_now_init() != ESP_OK) {
    Serial.println("ESP-NOW init failed!");
    esp_restart();
  }
  esp_now_register_recv_cb(onEspNowRecv);
  esp_now_register_send_cb(onEspNowSend);
  esp_wifi_set_channel(ESPNOW_CHANNEL, WIFI_SECOND_CHAN_NONE);

  // Init MQTT
  mqtt.setServer(TB_HOST, TB_PORT);
  mqtt.setBufferSize(4096*4, 4096*4);
  mqtt.setCallback(mqttCallback);

  // Queues
  qFromNodes = xQueueCreate(10, sizeof(GwPacket));

  // Auto-connect first node publish "connect"
  // (we do it lazily when first telemetry arrives)

  Serial.println("Gateway ready.");
}

// ============================== LOOP ====================================
void loop() {
  ensureMqtt();
  mqtt.loop();

  GwPacket pkt;
  while (xQueueReceive(qFromNodes, &pkt, 0) == pdTRUE) {

    String macStr = macToStr(pkt.mac);   // ← valid uint8_t[6] now

    /* 1️⃣ Send implicit "connect" (once per node) */
    DynamicJsonDocument conn(64);
    conn["device"] = macStr;
    char buf[64];
    size_t n = serializeJson(conn, buf);
    mqtt.publish("v1/gateway/connect", buf, n);

    /* 1️⃣-b Subscribe to shared attrs (only once) */              // ★
    static std::set<String> subs;                                  // ★
    if (!subs.count(macStr)) {                                     // ★
      String subMsg = "{\"device\":\"" + macStr + "\"}";           // ★
      mqtt.publish("v1/gateway/attributes", subMsg.c_str());       // ★
      subs.insert(macStr);                                         // ★
    }

    /* 2️⃣ Forward telemetry / attributes / RPC response */
    gatewayPublish(macStr, pkt.type, pkt.json, pkt.reqId);
  }

  delay(10);
}
