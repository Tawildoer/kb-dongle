# KB Dongle

A software KVM for your keyboard and trackpad. Plug the dongle into any machine and your Mac keyboard controls it — no drivers, no pairing, no KVM switch.

## How it works

```
Mac keyboard → KBDongle app (BLE) → Dongle → USB HID → Target machine
```

- **KBDongle.app** runs in the Mac menu bar. It intercepts keystrokes and mouse events and forwards them over BLE to the dongle.
- **The dongle** (ESP32-S3) receives the reports and presents as a standard USB HID keyboard + mouse to whatever it's plugged into.
- **The target machine** sees a wired USB keyboard. No software, no drivers.

Switch between local and remote with **CMD+Shift+1/2** (or any slot up to 9). A HUD overlay confirms the switch.

## Repo structure

```
firmware/        ESP-IDF firmware for the dongle (C, NimBLE, TinyUSB)
macos-app/       macOS menu bar app (Swift, SwiftUI, CoreBluetooth)
receiver-app/    Temporary test receiver for use with ESP32-C3 (see Testing)
```

## Hardware

**Target (final):** ESP32-S3 — has USB OTG, presents as USB HID keyboard + mouse natively.

**Current dev board:** ESP32-C3 — no USB OTG. Used with the `receiver-app` test shim while S3 boards arrive.

## Building

### Firmware (ESP-IDF 5.x)

```bash
cd firmware
source ~/esp/esp-idf/export.sh
idf.py build
idf.py -p /dev/cu.usbmodem* flash
```

### macOS app

Requires a self-signed code signing identity named `KBDongle Local Dev` in your keychain (for stable Accessibility TCC across rebuilds).

```bash
cd macos-app
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -scheme KBDongle -configuration Debug \
  CODE_SIGN_IDENTITY="KBDongle Local Dev" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="" \
  build
```

Grant **Accessibility** permission when prompted (System Settings → Privacy & Security → Accessibility). Required for keystroke interception.

### Test receiver (C3 only)

```bash
cd receiver-app
swiftc KBReceiver.swift -o KBReceiver -framework CoreGraphics -framework AppKit
```

Run on any Mac with the C3 plugged in via USB. Requires Accessibility permission.

## Usage

1. Plug the dongle into the target machine
2. Launch **KBDongle.app** on your Mac
3. The dongle connects automatically over BLE
4. **CMD+Shift+1** — local mode (your Mac)
5. **CMD+Shift+2** — remote mode (keystrokes go to target)

A HUD overlay shows the active slot on each switch. Disconnecting the dongle automatically returns to local mode.

## Status

| Component | Status |
|-----------|--------|
| BLE connection (Mac ↔ dongle) | Working |
| Keystroke interception + forwarding | Working |
| Mouse forwarding | Working |
| Slot switching (CMD+Shift+N) | Working |
| HUD overlay | Working |
| USB HID output (S3) | Pending — boards on order |
| USB HID output (C3 test shim) | Working via `receiver-app` |
