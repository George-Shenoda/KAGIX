# Kagix Smart Home — Flutter Mobile App (`MCT 331s`)

Mobile companion application for the **Kagix** Smart Home prototype (**Ain Shams University — Faculty of Engineering — Mechatronics Engineering Department, MCT 331s: Mechatronic System Integration, Fall 2026**).

Built with Flutter (Material 3) to communicate over **Bluetooth Classic (HC-05 / HC-06 SPP at 9600 baud)** and operate **alongside** all physical hardware inputs in real time.

## System Features & "Alongside" Hardware Synchronization

| Subsystem | Physical Hardware Control | Kagix Mobile App Control ("Alongside" Sync) |
| :--- | :--- | :--- |
| **1. Main Door Access** | 4x4 Keypad opens servo door lock and starts preset 5s auto-close countdown. | Opens or closes door directly or via virtual PIN pad (`1234`); displays live countdown and last trigger source (`Physical Keypad` vs. `Kagix App`). |
| **2. Security System** | Reed/limit switch on window triggers buzzer alarm when armed; PIR sensor turns on exterior light on door motion. | Arms/disarms Security Mode, displays an immediate red breach alert banner + floating message when the window opens while armed, Silences alarm, and shows live motion/exterior light state. |
| **3. Indoor Lighting** | LDR turns indoor light ON below ambient threshold; physical push button overrides manually. | Toggles between **Auto (LDR)** and **Manual (Btn + App)** modes and switches the indoor light ON/OFF in sync with the physical button. |
| **4. Climate Control** | DHT11/DHT22 reads Temp & Humidity; potentiometer knob (`A0`) sets fan trigger threshold. | Displays live Temperature (°C) and Humidity (%) gauges; syncs slider with the physical knob in real time or lets you adjust the threshold / fan state from your phone. |
| **5. 16x2 LCD Feedback** | Physical 16x2 LCD shows Door status, Security mode, and Temp/Humidity readings. | Mirrors the exact 2-line 16x2 LCD character display (`KAGIX D:CLSD S:ARM` / `T:26.5C H:48% F:OFF`) at the top of the app. |

## Building the Production Android APK & iOS IPA

### Option A: Automated Cloud Build via GitHub Actions (No Local SDK or Mac Required)

The included `.github/workflows/release_apk_ipa.yml` workflow compiles both the **Android Release APK** (`ubuntu-latest`) and the **iOS Release IPA** (`macos-latest`) in the cloud:

1. Extract `kagix_smart_home_project.zip` and push it to a new GitHub repository.
2. Open the **Actions** tab in your GitHub repository and select **Build Kagix Production Android APK & iOS IPA**.
3. Download **`Kagix-Smart-Home-Android-APK`** (`app-release.apk`) and **`Kagix-Smart-Home-iOS-IPA`** (`Kagix-Smart-Home-iOS.ipa`) directly from the workflow run artifacts.

### Option B: Local Command-Line Production Build

1. Initialize the platform folders and pull packages:
   ```bash
   flutter create --project-name kagix_smart_home --org com.kagix .
   flutter pub get
   ```
2. **Build Production Android APK** (works on Windows, macOS, or Linux with Android Studio / SDK):
   ```bash
   flutter build apk --release
   ```
   The installable production APK is generated at `build/app/outputs/flutter-apk/app-release.apk`.
3. **Build Production iOS IPA** (requires macOS with Xcode):
   ```bash
   flutter build ipa --release
   ```
   *(Or run `flutter build ios --release --no-codesign` for an unsigned build if you are sideloading via AltStore/Sideloadly).*

> **Important Hardware Note for iOS vs. Android Bluetooth**:
> * **Android (`.apk`)**: Works directly with **HC-05 / HC-06** Bluetooth Classic SPP modules using `flutter_bluetooth_serial`.
> * **iOS (`.ipa`)**: Apple restricts classic Bluetooth SPP (`HC-05`/`HC-06`) on iPhones to MFi-certified hardware. If any team member wants to control the Kagix house from an iPhone, connect a **BLE module** (such as **HM-10** or **ESP32 BLE**) to the Arduino TX/RX pins—the UI and `TEMP:...,HUM:...,DOOR:...` serial protocol remain identical.

## Bluetooth Classic Serial Protocol (`9600` Baud, Newline-Delimited `\n`)

### Outgoing Commands (`App -> Arduino TX`)

* `DOOR:OPEN` / `DOOR:CLOSE` / `PIN:1234` — Unlocks or locks the main door servo.
* `SEC:1` / `SEC:0` / `ALARM:CLEAR` — Arms/disarms security mode or clears an active window breach alarm.
* `LAUTO:1` / `LAUTO:0` / `LIGHT:1` / `LIGHT:0` — Sets indoor lighting mode (LDR Auto vs. Manual) or toggles the indoor light.
* `FAUTO:1` / `FAUTO:0` / `THR:28.5` / `FAN:1` / `FAN:0` — Sets climate control mode, updates the fan temperature threshold (°C), or toggles the fan manually.

### Incoming Telemetry Frame (`Arduino -> App RX`)

Send comma-separated key-value lines terminated by `\n` (every 500 ms or on any sensor/button change):

```text
TEMP:26.5,HUM:48,THR:28.0,TSRC:KNOB,DOOR:0,REM:0,DSRC:KEYPAD,SEC:1,WIN:0,MOT:0,LIN:0,LAUTO:1,LSRC:LDR,FAN:0,FAUTO:1,LUX:420
```
