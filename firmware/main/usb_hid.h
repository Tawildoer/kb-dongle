#pragma once
#include <stdint.h>
void usb_hid_init(void);
void usb_hid_keyboard_report(uint8_t modifier, uint8_t keycodes[6]);
void usb_hid_mouse_report(uint8_t buttons, int8_t dx, int8_t dy, int8_t scroll);
