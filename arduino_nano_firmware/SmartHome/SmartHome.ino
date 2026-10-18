#include <Wire.h>
#include <Adafruit_NeoPixel.h>
#include <dht.h>

#include "Light.h"
#include "ClimateControl.h"
#include "DoorControl.h"
#include "DisplayManager.h"
#include "BluetoothManager.h"
#include "SecuritySystem.h"

// ============================================================================
// ARDUINO NANO COMPLETE PINOUT (22/22 PINS — ZERO CONFLICTS, ZERO SHARED PARTS)
// ============================================================================
// 1. Main Door Access:
//    - D2:        SG90 Door Servo Motor
//    - D13..D10:  4x4 Keypad Rows R1..R4 (13, 12, 11, 10)
//    - A1:        4x4 Keypad Columns C1..C4 (via resistor network or I2C)
// 2. Security System (100% Dedicated Hardware):
//    - D8:        Switch #2 (Security Arm/Disarm Toggle Switch)
//    - A2 (D16):  Window Intruder IR2 Sensor (Active LOW)
//    - A3 (D17):  Main Door PIR Motion Sensor (Active HIGH)
//    - D5:        Active Piezo Alarm Buzzer
//    - D7:        Matrix LED #2 (8x8 NeoPixel Matrix for Exterior Motion Light)
// 3. Automatic Indoor Lighting System (100% Dedicated Hardware):
//    - D3:        Switch #1 (Indoor Light Manual Override Button/Switch)
//    - A0:        LDR Photoresistor Ambient Light Sensor
//    - A6:        Potentiometer #1 (Indoor Light LDR Threshold Knob — 10k)
//    - D6:        Matrix LED #1 (8x8 NeoPixel Matrix for Indoor Room Light)
// 4. Climate Control System (100% Dedicated Hardware):
//    - D4:        DHT11 Temperature & Humidity Sensor
//    - A7:        Potentiometer #2 (Climate Temperature Threshold Knob — 10k)
//    - D9:        5V DC Cooling Fan Motor (via NPN Transistor / Relay Driver)
// 5. LCD Feedback Display & Wireless Bluetooth Link:
//    - A4 (SDA):  16x2 I2C LCD Display SDA
//    - A5 (SCL):  16x2 I2C LCD Display SCL
//    - D0 (RX):   HC-05 Bluetooth TXD
//    - D1 (TX):   HC-05 Bluetooth RXD (via 1k/2k voltage divider)
// ============================================================================

// ==========================================
// HARDWARE INITIALIZATION (2 SEPARATE 8x8 MATRIX LEDs)
// ==========================================
// Matrix LED #1 (Pin D6): Dedicated exclusively to Function 3 (Indoor Lighting)
Adafruit_NeoPixel matrixIndoor(MATRIX_LED_COUNT, MATRIX_INDOOR_PIN, NEO_GRB + NEO_KHZ800);

// Matrix LED #2 (Pin D7): Dedicated exclusively to Function 2 (Security Exterior Light)
Adafruit_NeoPixel matrixSecurity(SEC_MATRIX_LED_COUNT, SEC_MATRIX_PIN, NEO_GRB + NEO_KHZ800);

dht DHT;

// ==========================================
// CLASS OBJECTS (NO 2 FUNCTIONS SHARE ANY SENSOR OR ACTUATOR)
// ==========================================
// Function 3 — Indoor Lighting: Switch #1 = D3, LDR = A0, Potentiometer #1 = A6
Light light = Light(3, A0, A6);

// Function 4 — Climate Control: DHT11 = D4, Fan Motor = D9, Potentiometer #2 = A7
ClimateControl climate = ClimateControl(4, 9, A7);

// Function 1 — Main Door Access: Servo = D2, Password = "2006"
DoorControl door = DoorControl(2, "2006");

// Function 5 — LCD Feedback Display: I2C Address 0x27 (16x2) on A4 (SDA) & A5 (SCL)
DisplayManager display = DisplayManager(0x27, 16, 2);

// Wireless Link — Bluetooth Classic SPP on D0 (RX) & D1 (TX)
BluetoothManager bluetooth;

// Function 2 — Security System: Switch #2 = D8, Window IR2 = A2, Door PIR = A3, Buzzer = D5
// (Uses dedicated matrixSecurity on Pin D7 for the Exterior Motion Light)
SecuritySystem security = SecuritySystem(8, A2, A3, 5);

// ==========================================
// GLOBAL STATE VARIABLES (Used by Bluetooth)
// ==========================================
bool isSecurityArmed   = true;
bool isWindowOpen      = false;
bool isMotionDetected  = false;
bool isFanOn           = false;
float currentTemp      = 0.0;
float currentHum       = 0.0;
float tempThreshold    = 28.0;

unsigned long lastUpdateMillis = 0;

void setup() {
  // Input Pin Setups
  pinMode(light.lightSwitch, INPUT_PULLUP);
  pinMode(light.LDR, INPUT);

  // Begin Subsystems
  bluetooth.begin(9600);
  display.begin();

  // Initialize Matrix LED #1 (Indoor Light on D6)
  matrixIndoor.begin();
  matrixIndoor.setBrightness(MATRIX_BRIGHTNESS);
  matrixIndoor.clear();
  matrixIndoor.show();

  // Initialize Matrix LED #2 (Security Exterior Motion Light on D7)
  matrixSecurity.begin();
  matrixSecurity.setBrightness(SEC_MATRIX_BRIGHTNESS);
  matrixSecurity.clear();
  matrixSecurity.show();

  light.begin();
  climate.begin();
  door.begin();
  security.begin();

  // Initial screen write
  display.update(door.getIsOpen(), isSecurityArmed, currentTemp, currentHum);
}

void loop() {
  // Fast Background Tasks
  light.LDRCheck();
  light.toggleLightBtn();
  climate.update();
  door.update();
  security.update();
  bluetooth.readCommand();

  // Screen and Bluetooth Update (Every 500ms)
  if (millis() - lastUpdateMillis >= 500) {
    lastUpdateMillis = millis();
    display.update(door.getIsOpen(), isSecurityArmed, currentTemp, currentHum);
    bluetooth.sendStatus();
  }
}
