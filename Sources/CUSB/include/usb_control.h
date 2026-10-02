#pragma once
#include <stdint.h>

/// Sends a request on the default control pipe of the USB device at `location_id`
/// (the IORegistry "locationID" property). Works without opening the device or claiming any
/// interface, so it does not conflict with drivers macOS may have attached.
/// Returns 0 (kIOReturnSuccess) on success, otherwise an IOReturn error code.
int usb_control_transfer(uint32_t location_id,
                         uint8_t request_type, uint8_t request,
                         uint16_t value, uint16_t index,
                         void *data, uint16_t length,
                         uint32_t timeout_ms, uint32_t *transferred);
