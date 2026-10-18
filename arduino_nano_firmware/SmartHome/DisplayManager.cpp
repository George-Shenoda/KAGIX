#include "DisplayManager.h"

DisplayManager::DisplayManager(uint8_t addr, uint8_t cols, uint8_t rows) : lcd(addr, cols, rows) {
}

void DisplayManager::begin() {
  lcd.init();
  lcd.backlight();
}

void DisplayManager::update(bool isDoorOpen, bool isSecArmed, float temp, float hum) {
  String doorStr = isDoorOpen ? "OPENED" : "CLOSED";
  String secStr  = isSecArmed ? "ARM" : "OFF";
  String firstLine = String("D:") + doorStr + " S:" + secStr;
  while (firstLine.length() < 16) firstLine += " ";

  // Fixed: HD44780 16x2 LCD character ROM uses 223 (0xDF) for degree symbol
  char degree = (char)223;
  String secondLine = String("T:") + String(temp, 1) + degree + "C H:" + String((int)hum) + "%";
  while (secondLine.length() < 16) secondLine += " ";

  lcd.setCursor(0, 0);
  lcd.print(firstLine);

  lcd.setCursor(0, 1);
  lcd.print(secondLine);
}
