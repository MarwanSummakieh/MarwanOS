# Controller wake investigation — 7 October 2026

**Controller-button wake: user-reported failure; unresolved.** The owner reports that PC1 cannot be woken with the controller after entering sleep. Live read-only inspection was possible after PC1 returned from sleep. No new suspend, reboot, driver change, or wake-policy change was performed during this investigation.

## Live evidence

- PC1 is reachable again at `192.168.50.206`.
- `/sys/power/mem_sleep`: `s2idle [deep]`.
- Kernel suspend counters: `success=1`, `fail=0`. The current boot journal records a deep-suspend entry and a subsequent resume. This establishes a kernel sleep/resume cycle, not controller wake or full display/audio/game recovery.
- Attached controller: USB Sony DualSense, `054c:0ce6`, device `1-1`, on PCI USB host `0000:00:14.0`.
- `lsusb -v -d 054c:0ce6` reports configuration `bmAttributes 0xc0` (self-powered) with no Remote Wakeup flag.
- The controller has no `/sys/bus/usb/devices/1-1/power/wakeup` attribute.
- PCI host wake is `enabled`; ACPI `XHC` wake is also enabled.
- USB root hub `usb1/power/wakeup` is `disabled`.
- The attached HP keyboard exposes `power/wakeup=enabled`. Its ability to wake this machine was not tested.
- No `/sys/class/bluetooth` exists, and the USB inventory contains no Bluetooth adapter.

## Interpretation

The currently connected controller does not expose a supported USB remote-wake capability to Linux. There is therefore no controller wake switch to enable through ordinary sysfs/udev configuration. Host-controller wake is already enabled; root-hub wake is separately disabled. Enabling that hub alone would not establish that DualSense button presses generate a usable wake request.

Linux documents remote wake as a device capability, distinct from allowing an idle device to autosuspend. Setting `power/control=on` only prevents runtime autosuspend and does not keep the device operating through system suspend. See the [kernel USB power-management documentation](https://docs.kernel.org/driver-api/usb/power-management.html).

For recovery, use a short press of PC1's physical power button. Controller wake remains a hardware/transport acceptance requirement: any alternative controller/receiver or Bluetooth path must expose wake capability and pass an actual button-wake test on this machine. A Bluetooth adapter alone is not a guarantee. A screen-off mode that keeps the OS awake could support controller activation, but would be a different feature from deep sleep and has not been implemented here.

This finding supersedes the earlier generic “sleep testing deferred” status for the specific reported controller-wake issue. It does not turn the earlier local automated passes into hardware sleep/wake acceptance.
