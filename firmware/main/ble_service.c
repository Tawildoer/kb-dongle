#include "ble_service.h"
#include "esp_log.h"
#include "nvs_flash.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "host/ble_hs.h"
#include "host/util/util.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"
#include <string.h>
#include <stdio.h>

static const char *TAG = "ble_service";

static const ble_uuid128_t svc_uuid = BLE_UUID128_INIT(
    0x02,0x00,0x12,0xac,0x42,0x02,0x56,0xbe,
    0xee,0x11,0x3a,0x1c,0xd0,0xe8,0xb5,0xa8);

static const ble_uuid128_t key_uuid = BLE_UUID128_INIT(
    0x02,0x00,0x12,0xac,0x42,0x02,0x56,0xbe,
    0xee,0x11,0x3a,0x1c,0xd1,0xe8,0xb5,0xa8);

static const ble_uuid128_t mouse_uuid = BLE_UUID128_INIT(
    0x02,0x00,0x12,0xac,0x42,0x02,0x56,0xbe,
    0xee,0x11,0x3a,0x1c,0xd2,0xe8,0xb5,0xa8);

static key_report_cb_t s_key_cb;
static mouse_report_cb_t s_mouse_cb;

static int key_report_write_cb(uint16_t conn_handle, uint16_t attr_handle,
                                struct ble_gatt_access_ctxt *ctxt, void *arg) {
    (void)conn_handle; (void)attr_handle; (void)arg;
    if (ctxt->op != BLE_GATT_ACCESS_OP_WRITE_CHR) return BLE_ATT_ERR_UNLIKELY;
    if (OS_MBUF_PKTLEN(ctxt->om) != 8) return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
    uint8_t data[8];
    os_mbuf_copydata(ctxt->om, 0, 8, data);
    if (s_key_cb) s_key_cb(data);
    return 0;
}

static int mouse_report_write_cb(uint16_t conn_handle, uint16_t attr_handle,
                                  struct ble_gatt_access_ctxt *ctxt, void *arg) {
    (void)conn_handle; (void)attr_handle; (void)arg;
    if (ctxt->op != BLE_GATT_ACCESS_OP_WRITE_CHR) return BLE_ATT_ERR_UNLIKELY;
    if (OS_MBUF_PKTLEN(ctxt->om) != 4) return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
    uint8_t data[4];
    os_mbuf_copydata(ctxt->om, 0, 4, data);
    if (s_mouse_cb) s_mouse_cb(data);
    return 0;
}

static const struct ble_gatt_chr_def s_chars[] = {
    { .uuid = &key_uuid.u, .access_cb = key_report_write_cb, .flags = BLE_GATT_CHR_F_WRITE_NO_RSP },
    { .uuid = &mouse_uuid.u, .access_cb = mouse_report_write_cb, .flags = BLE_GATT_CHR_F_WRITE_NO_RSP },
    { 0 },
};

static const struct ble_gatt_svc_def s_services[] = {
    { .type = BLE_GATT_SVC_TYPE_PRIMARY, .uuid = &svc_uuid.u, .characteristics = s_chars },
    { 0 },
};

static void ble_app_advertise(void) {
    struct ble_gap_adv_params adv_params = {0};
    adv_params.conn_mode = BLE_GAP_CONN_MODE_UND;
    adv_params.disc_mode = BLE_GAP_DISC_MODE_GEN;
    uint8_t own_addr[6];
    ble_hs_id_copy_addr(BLE_ADDR_PUBLIC, own_addr, NULL);
    char name[16];
    snprintf(name, sizeof(name), "KBDongle-%02X%02X", own_addr[1], own_addr[0]);
    ble_svc_gap_device_name_set(name);
    struct ble_hs_adv_fields fields = {0};
    fields.flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;
    fields.name = (uint8_t *)name;
    fields.name_len = strlen(name);
    fields.name_is_complete = 1;
    ble_gap_adv_set_fields(&fields);
    ble_gap_adv_start(BLE_OWN_ADDR_PUBLIC, NULL, BLE_HS_FOREVER, &adv_params, NULL, NULL);
    ESP_LOGI(TAG, "Advertising as: %s", name);
}

static void ble_on_sync(void) { ble_hs_util_ensure_addr(0); ble_app_advertise(); }
static void ble_on_reset(int reason) { ESP_LOGE(TAG, "BLE reset, reason=%d", reason); }

static void nimble_host_task(void *param) {
    nimble_port_run();
    nimble_port_freertos_deinit();
}

void ble_service_init(key_report_cb_t on_key, mouse_report_cb_t on_mouse) {
    s_key_cb = on_key;
    s_mouse_cb = on_mouse;
    nimble_port_init();
    ble_hs_cfg.sync_cb = ble_on_sync;
    ble_hs_cfg.reset_cb = ble_on_reset;
    ble_hs_cfg.store_status_cb = ble_store_util_status_rr;
    ble_svc_gap_init();
    ble_svc_gatt_init();
    ble_gatts_count_cfg(s_services);
    ble_gatts_add_svcs(s_services);
    nimble_port_freertos_init(nimble_host_task);
    ESP_LOGI(TAG, "BLE service initialised");
}
