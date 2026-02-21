#include <WiFi.h>
#include <WebServer.h>
#include <Wire.h>
#include <RTClib.h>
#include <LittleFS.h>
#include <ArduinoJson.h>
#include <ESPmDNS.h>
#include "time.h"

#define RELAY_PIN 3
#define SDA_PIN 8
#define SCL_PIN 9
#define RELAY_ON  HIGH   
#define RELAY_OFF LOW  

RTC_DS3231 rtc;
WebServer server(80);

struct Lesson { int start; int end; };
std::vector<Lesson> weekSchedule[7];
bool daysActive[7] = {true, true, true, true, true, false, false}; 
bool globalMute = false; 

String wifi_ssid = "";
String wifi_pass = "";
bool isApMode = false;

unsigned long lastBellCheck = 0;
bool bellActive = false;
unsigned long bellStartTime = 0;
unsigned long currentBellDuration = 3000; 

void sendCORS() {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.sendHeader("Access-Control-Allow-Methods", "POST,GET,OPTIONS");
  server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
}

int timeToMin(String t) {
  int sep = t.indexOf(':'); if (sep == -1) return -1;
  return t.substring(0, sep).toInt() * 60 + t.substring(sep + 1).toInt();
}

void loadConfig() {
  if (LittleFS.exists("/data.json")) {
    File file = LittleFS.open("/data.json", "r");
    DynamicJsonDocument doc(16384);
    DeserializationError error = deserializeJson(doc, file);
    file.close();
    if (!error) {
      if (doc.containsKey("ssid")) wifi_ssid = doc["ssid"].as<String>();
      if (doc.containsKey("pass")) wifi_pass = doc["pass"].as<String>();
      globalMute = doc["mute"] | false; 
      JsonArray scheduleArr = doc["schedule"];
      for (int i = 0; i < 7; i++) {
        weekSchedule[i].clear();
        JsonArray dayLessons = scheduleArr[i].as<JsonArray>();
        for (JsonObject l : dayLessons) {
          weekSchedule[i].push_back({timeToMin(l["s"].as<String>()), timeToMin(l["e"].as<String>())});
        }
      }
      for (int i = 0; i < 7; i++) daysActive[i] = doc["days"][i];
    }
  }
}

void saveToFile() {
  DynamicJsonDocument doc(16384);
  doc["ssid"] = wifi_ssid;
  doc["pass"] = wifi_pass;
  doc["mute"] = globalMute;
  JsonArray scheduleArr = doc.createNestedArray("schedule");
  for (int i = 0; i < 7; i++) {
    JsonArray dayArr = scheduleArr.createNestedArray();
    for (Lesson l : weekSchedule[i]) {
      JsonObject obj = dayArr.createNestedObject();
      char buf[6]; sprintf(buf, "%02d:%02d", l.start / 60, l.start % 60);
      obj["s"] = String(buf); sprintf(buf, "%02d:%02d", l.end / 60, l.end % 60); obj["e"] = String(buf);
    }
  }
  JsonArray daysArr = doc.createNestedArray("days");
  for (int i = 0; i < 7; i++) daysArr.add(daysActive[i]);
  File file = LittleFS.open("/data.json", "w");
  serializeJson(doc, file);
  file.close();
}

void handleSetWifi() {
  sendCORS();
  String s = server.arg("ssid");
  String p = server.arg("pass");
  if (s.length() > 0) {
    wifi_ssid = s;
    wifi_pass = p;
    saveToFile();
    server.send(200, "text/plain", "Saved. Restarting...");
    delay(1000);
    ESP.restart();
  } else server.send(400, "text/plain", "Bad SSID");
}

void handleReset() {
  sendCORS();
  LittleFS.format();
  server.send(200, "text/plain", "Resetting...");
  delay(1000);
  ESP.restart();
}

void handleTime() {
  sendCORS();
  DateTime now = rtc.now();
  char buf[30];
  sprintf(buf, "%02d.%02d.%04d %02d:%02d:%02d", now.day(), now.month(), now.year(), now.hour(), now.minute(), now.second());
  server.send(200, "text/plain", buf);
}

void handleManualBell() {
  sendCORS();
  if (!bellActive) {
    digitalWrite(RELAY_PIN, RELAY_ON);
    bellActive = true;
    bellStartTime = millis();
    currentBellDuration = 5000;
  }
  server.send(200, "text/plain", "OK");
}

void handleData() {
  sendCORS();
  DynamicJsonDocument doc(16384);
  doc["mute"] = globalMute;
  doc["ssid"] = wifi_ssid;
  JsonArray scheduleArr = doc.createNestedArray("schedule");
  for (int i = 0; i < 7; i++) {
    JsonArray dayArr = scheduleArr.createNestedArray();
    for (Lesson l : weekSchedule[i]) {
      JsonObject obj = dayArr.createNestedObject();
      char buf[6]; sprintf(buf, "%02d:%02d", l.start / 60, l.start % 60);
      obj["s"] = String(buf); sprintf(buf, "%02d:%02d", l.end / 60, l.end % 60); obj["e"] = String(buf);
    }
  }
  JsonArray daysArr = doc.createNestedArray("days");
  for (int i = 0; i < 7; i++) daysArr.add(daysActive[i]);
  String json; serializeJson(doc, json);
  server.send(200, "application/json", json);
}

void handleSave() {
  sendCORS();
  if (server.hasArg("plain")) {
    DynamicJsonDocument doc(16384);
    if (!deserializeJson(doc, server.arg("plain"))) {
      globalMute = doc["mute"];
      JsonArray sch = doc["schedule"];
      for(int i=0; i<7; i++) {
        weekSchedule[i].clear();
        JsonArray d = sch[i];
        for(JsonObject l : d) weekSchedule[i].push_back({timeToMin(l["s"]), timeToMin(l["e"])});
      }
      JsonArray da = doc["days"];
      for(int i=0; i<7; i++) daysActive[i] = da[i];
      saveToFile();
      server.send(200, "text/plain", "OK");
    }
  } else server.send(400);
}

void handleAdjust() {
  sendCORS();
  String type = server.arg("type"); int val = server.arg("val").toInt(); DateTime now = rtc.now();
  if (type == "h") rtc.adjust(now + TimeSpan(0, val, 0, 0)); if (type == "m") rtc.adjust(now + TimeSpan(0, 0, val, 0));
  server.send(200, "text/plain", "OK");
}

void handleAdjustDate() {
    sendCORS();
    String type = server.arg("type"); int val = server.arg("val").toInt(); DateTime now = rtc.now();
    if (type == "d") rtc.adjust(now + TimeSpan(val, 0, 0, 0));
    else if (type == "mo") {
        int nM = now.month() + val; int nY = now.year();
        if (nM > 12) { nM = 1; nY++; } if (nM < 1) { nM = 12; nY--; }
        rtc.adjust(DateTime(nY, nM, now.day(), now.hour(), now.minute(), now.second()));
    }
    server.send(200, "text/plain", "OK");
}

void handleOptions() { sendCORS(); server.send(204); }

void setup() {
  Serial.begin(115200);
  digitalWrite(RELAY_PIN, RELAY_OFF); pinMode(RELAY_PIN, OUTPUT);
  Wire.begin(SDA_PIN, SCL_PIN); 
  if (!rtc.begin()) Serial.println("RTC Fail");
  LittleFS.begin(true);

  loadConfig();

  if (wifi_ssid.length() > 0) {
    IPAddress local_IP(192, 168, 1, 104);
    IPAddress gateway(192, 168, 1, 1);
    IPAddress subnet(255, 255, 255, 0);
    IPAddress primaryDNS(8, 8, 8, 8);
    WiFi.config(local_IP, gateway, subnet, primaryDNS);
    
    WiFi.mode(WIFI_STA);
    WiFi.begin(wifi_ssid.c_str(), wifi_pass.c_str());
    int attempts = 0;
    while (WiFi.status() != WL_CONNECTED && attempts < 20) { delay(500); Serial.print("."); attempts++; }
  }

  if (WiFi.status() != WL_CONNECTED) {
    isApMode = true;
    WiFi.mode(WIFI_AP);
    WiFi.softAP("SchoolBell_Setup", "12345678");
    Serial.println("\nAP Mode: 192.168.4.1");
  } else {
    Serial.println("\nWiFi Connected! IP: 192.168.1.104");
    if (MDNS.begin("zvonok")) Serial.println("mDNS started");
    configTime(10800, 0, "pool.ntp.org"); 
    struct tm ti; 
    if (getLocalTime(&ti, 5000)) { 
      if (ti.tm_year + 1900 > 2024) {
        rtc.adjust(DateTime(ti.tm_year + 1900, ti.tm_mon + 1, ti.tm_mday, ti.tm_hour, ti.tm_min, ti.tm_sec));
        Serial.println("Часы DS3231 синхронизированы с интернетом!");
      }
    }
  }

  server.on("/data", HTTP_GET, handleData);
  server.on("/time", HTTP_GET, handleTime);
  server.on("/save", HTTP_POST, handleSave);
  server.on("/manual", HTTP_POST, handleManualBell);
  server.on("/adjust", HTTP_POST, handleAdjust);
  server.on("/adjustDate", HTTP_POST, handleAdjustDate);
  server.on("/setwifi", HTTP_POST, handleSetWifi);
  server.on("/reset", HTTP_POST, handleReset);

  server.on("/data", HTTP_OPTIONS, handleOptions);
  server.on("/save", HTTP_OPTIONS, handleOptions);
  server.on("/manual", HTTP_OPTIONS, handleOptions);
  server.on("/adjust", HTTP_OPTIONS, handleOptions);
  server.on("/adjustDate", HTTP_OPTIONS, handleOptions);
  server.on("/setwifi", HTTP_OPTIONS, handleOptions);
  server.on("/reset", HTTP_OPTIONS, handleOptions);
  server.on("/time", HTTP_OPTIONS, handleOptions);

  server.begin();
}

void loop() {
  server.handleClient();
  if (bellActive && millis() - bellStartTime > currentBellDuration) { digitalWrite(RELAY_PIN, RELAY_OFF); bellActive = false; }
  
  if (millis() - lastBellCheck > 1000) {
    lastBellCheck = millis();
    DateTime now = rtc.now();
    int myIdx = (now.dayOfTheWeek() == 0) ? 6 : now.dayOfTheWeek() - 1;
    
    if (!globalMute && daysActive[myIdx]) {
      int curMin = now.hour() * 60 + now.minute();
      for (Lesson l : weekSchedule[myIdx]) {
        if ((l.start == curMin || l.end == curMin) && now.second() == 0) {
          if (!bellActive) {
            digitalWrite(RELAY_PIN, RELAY_ON);
            bellActive = true;
            bellStartTime = millis();
            currentBellDuration = 3000;
          }
        }
      }
    }
  }
}