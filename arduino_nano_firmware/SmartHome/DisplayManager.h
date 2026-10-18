#ifndef DISPLAYMANAGER_H
#define DISPLAYMANAGER_H

#include <Arduino.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>

class DisplayManager {
  private:
    LiquidCrystal_I2C lcd;
  public:
    DisplayManager(uint8_t addr, uint8_t cols, uint8_t rows);
    void begin();
    void update(bool isDoorOpen, bool isSecArmed, float temp, float hum);
};

#endif
