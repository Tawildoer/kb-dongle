#include "usb_hid.h"
#include "esp_log.h"
#include <string.h>

/*
 * NOTE: ESP32-C3 has USB Serial/JTAG (CDC) only — it does NOT have a USB OTG
 * controller, so TinyUSB HID is not supported on this chip variant.
 * This module provides the correct API surface; HID reports are logged for
 * debugging.  A future hardware revision using ESP32-S3 or ESP32-S2 would
 * replace this with a full TinyUSB composite HID implementation.
 */

static const char *TAG = "usb_hid";

void usb_hid_init(void) {
    ESP_LOGI(TAG, "USB HID stub initialised (ESP32-C3: no USB OTG)");
}

void usb_hid_keyboard_report(uint8_t modifier, uint8_t keycodes[6]) {
    ESP_LOGD(TAG, "KBD mod=0x%02x keys=[%02x %02x %02x %02x %02x %02x]",
             modifier,
             keycodes[0], keycodes[1], keycodes[2],
             keycodes[3], keycodes[4], keycodes[5]);
}

void usb_hid_mouse_report(uint8_t buttons, int8_t dx, int8_t dy, int8_t scroll) {
    ESP_LOGD(TAG, "MOUSE btn=0x%02x dx=%d dy=%d scroll=%d",
             buttons, dx, dy, scroll);
}
