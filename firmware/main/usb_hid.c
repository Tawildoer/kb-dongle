#include "usb_hid.h"
#include "esp_log.h"
#include "driver/usb_serial_jtag.h"
#include <string.h>

/*
 * Relays HID reports to the host Mac over USB CDC serial.
 * Frame format: [0xFE][0xFF][type][data...]
 *   type 0x01 = keyboard: modifier(1) + reserved(1) + keycodes(6) = 8 bytes → frame 11 bytes
 *   type 0x02 = mouse:    buttons(1) + dx(1) + dy(1) + scroll(1)  = 4 bytes → frame 7 bytes
 * 0xFE/0xFF are invalid UTF-8 and won't appear in ESP log output, making sync reliable.
 */

static const char *TAG = "usb_hid";

void usb_hid_init(void) {
    usb_serial_jtag_driver_config_t cfg = USB_SERIAL_JTAG_DRIVER_CONFIG_DEFAULT();
    esp_err_t err = usb_serial_jtag_driver_install(&cfg);
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
        ESP_LOGE(TAG, "driver install failed: %s", esp_err_to_name(err));
    }
    ESP_LOGI(TAG, "USB HID relay ready");
}

void usb_hid_keyboard_report(uint8_t modifier, uint8_t keycodes[6]) {
    uint8_t frame[11] = {0xFE, 0xFF, 0x01, modifier, 0x00,
                         keycodes[0], keycodes[1], keycodes[2],
                         keycodes[3], keycodes[4], keycodes[5]};
    usb_serial_jtag_write_bytes(frame, sizeof(frame), pdMS_TO_TICKS(20));
}

void usb_hid_mouse_report(uint8_t buttons, int8_t dx, int8_t dy, int8_t scroll) {
    uint8_t frame[7] = {0xFE, 0xFF, 0x02,
                        buttons, (uint8_t)dx, (uint8_t)dy, (uint8_t)scroll};
    usb_serial_jtag_write_bytes(frame, sizeof(frame), pdMS_TO_TICKS(20));
}
