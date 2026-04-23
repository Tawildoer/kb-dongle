#include <string.h>
#include "esp_log.h"
#include "nvs_flash.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"
#include "usb_hid.h"
#include "ble_service.h"

static const char *TAG = "main";

typedef enum { RPT_KEY, RPT_MOUSE } report_type_t;
typedef struct {
    report_type_t type;
    uint8_t data[8];
} hid_report_msg_t;

static QueueHandle_t s_hid_queue;

static void on_key_report(const uint8_t data[8]) {
    hid_report_msg_t msg = { .type = RPT_KEY };
    memcpy(msg.data, data, 8);
    xQueueSend(s_hid_queue, &msg, 0);
}

static void on_mouse_report(const uint8_t data[4]) {
    hid_report_msg_t msg = { .type = RPT_MOUSE };
    memcpy(msg.data, data, 4);
    xQueueSend(s_hid_queue, &msg, 0);
}

static void hid_sender_task(void *param) {
    (void)param;
    hid_report_msg_t msg;
    while (1) {
        if (xQueueReceive(s_hid_queue, &msg, portMAX_DELAY) == pdTRUE) {
            if (msg.type == RPT_KEY) {
                usb_hid_keyboard_report(msg.data[0], &msg.data[2]);
            } else {
                usb_hid_mouse_report(msg.data[0], (int8_t)msg.data[1],
                                     (int8_t)msg.data[2], (int8_t)msg.data[3]);
            }
        }
    }
}

void app_main(void) {
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);
    s_hid_queue = xQueueCreate(16, sizeof(hid_report_msg_t));
    usb_hid_init();
    ble_service_init(on_key_report, on_mouse_report);
    xTaskCreate(hid_sender_task, "hid_send", 4096, NULL, 10, NULL);
    ESP_LOGI(TAG, "KB Dongle ready");
}
