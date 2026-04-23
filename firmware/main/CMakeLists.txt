idf_component_register(
    SRCS
        "main.c"
        "usb_hid.c"
        "ble_service.c"
    INCLUDE_DIRS "."
    REQUIRES
        nvs_flash
        bt
        esp_driver_usb_serial_jtag
)
