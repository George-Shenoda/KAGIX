#ifndef CLIMATECONTROL_H
#define CLIMATECONTROL_H

#include <Arduino.h>

class ClimateControl {
  private:
    int dhtPin;
    int motorPin;
    int potPin;
    unsigned long lastDHTReadTime;

    bool isAutoMode;
    int lastPotValue;
    bool isThresholdOverridden;

  public:
    ClimateControl(int dPin, int mPin, int pPin);

    void begin();
    void setBluetoothThreshold(float newThr);
    void setManualFan(bool turnOn);
    void setAutoFan();
    void returnToPotentiometer();
    bool getIsAutoMode();
    void update();
};

#endif
