#pragma once
#include <stdint.h>
typedef void (*key_report_cb_t)(const uint8_t data[8]);
typedef void (*mouse_report_cb_t)(const uint8_t data[4]);
void ble_service_init(key_report_cb_t on_key, mouse_report_cb_t on_mouse);
