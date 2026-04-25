idf_component_register(
    SRCS
        "main.c"
        "usb_hid.c"
        "ble_service.c"
    INCLUDE_DIRS "."
    REQUIRES
        nvs_flash
        bt
    PRIV_REQUIRES
        esp_tinyusb
)
