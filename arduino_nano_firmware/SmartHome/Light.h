#ifndef LIGHT_H
#define LIGHT_H

#include <Arduino.h>

// Dedicated Matrix LED #1 on Pin D6 for Function 3 (Automatic Indoor Lighting)
#define MATRIX_INDOOR_PIN 6
#define MATRIX_LED_COUNT 64
#define MATRIX_BRIGHTNESS 50

class Light {
  private:
    bool isIndoorLightOn;
    int lastSwitchState;
    bool isAutoMode;
    unsigned long manualOverrideTimer;
    const unsigned long OVERRIDE_DURATION;

    // Dedicated Potentiometer #1 (A6) vs Bluetooth threshold
    int lastPotValue;
    bool isThresholdOverridden;
    int ldrThreshold;
    int lastLdrValue;

    int matrixBrightness;

  public:
    int lightSwitch;
    int LDR;
    int lightPOT;

    Light(int switchPin, int LDRPin, int potPin);

    void begin();
    void setBrightness(int newBrightness);
    int getBrightness();
    void setBluetoothThreshold(int newThr);
    int getThreshold();
    int getLastLDRValue();
    void returnToPotentiometer();
    void lightOn();
    void lightOff();
    void refreshMatrix();
    bool getIndoorLight();
    bool getIsAutoMode();
    void enableAutoMode();
    void disableAutoMode();
    void toggleLightBtn();
    void LDRCheck();
};

#endif
