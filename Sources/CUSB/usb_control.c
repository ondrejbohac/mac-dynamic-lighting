#include "usb_control.h"

#include <IOKit/IOCFPlugIn.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/usb/IOUSBLib.h>

static io_service_t find_device(uint32_t location_id) {
    CFMutableDictionaryRef match = IOServiceMatching("IOUSBHostDevice");
    if (!match) return IO_OBJECT_NULL;
    CFMutableDictionaryRef props = CFDictionaryCreateMutable(kCFAllocatorDefault, 1,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFNumberRef loc = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &location_id);
    CFDictionarySetValue(props, CFSTR(kUSBDevicePropertyLocationID), loc);
    CFDictionarySetValue(match, CFSTR(kIOPropertyMatchKey), props);
    CFRelease(loc);
    CFRelease(props);
    return IOServiceGetMatchingService(kIOMainPortDefault, match); // consumes `match`
}

int usb_control_transfer(uint32_t location_id,
                         uint8_t request_type, uint8_t request,
                         uint16_t value, uint16_t index,
                         void *data, uint16_t length,
                         uint32_t timeout_ms, uint32_t *transferred) {
    io_service_t svc = find_device(location_id);
    if (!svc) return kIOReturnNotFound;

    IOCFPlugInInterface **plugin = NULL;
    SInt32 score = 0;
    kern_return_t kr = IOCreatePlugInInterfaceForService(svc, kIOUSBDeviceUserClientTypeID,
                                                         kIOCFPlugInInterfaceID, &plugin, &score);
    IOObjectRelease(svc);
    if (kr != KERN_SUCCESS || !plugin) return kr != KERN_SUCCESS ? kr : kIOReturnError;

    IOUSBDeviceInterface182 **dev = NULL;
    HRESULT hr = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID182),
                                           (LPVOID *)&dev);
    IODestroyPlugInInterface(plugin);
    if (hr != S_OK || !dev) return kIOReturnError;

    IOUSBDevRequestTO req = {
        .bmRequestType = request_type,
        .bRequest = request,
        .wValue = value,
        .wIndex = index,
        .wLength = length,
        .pData = data,
        .noDataTimeout = timeout_ms,
        .completionTimeout = timeout_ms,
    };
    kr = (*dev)->DeviceRequestTO(dev, &req);
    if (transferred) *transferred = req.wLenDone;
    (*dev)->Release(dev);
    return kr;
}
