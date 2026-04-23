#pragma once
#include <stdint.h>

void ble_hid_register_services(void);
void ble_hid_add_conn(uint16_t handle);
void ble_hid_remove_conn(uint16_t handle);
void ble_hid_send_key(const uint8_t report[8]);
void ble_hid_send_mouse(const uint8_t report[4]);
