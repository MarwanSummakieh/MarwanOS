# Bluetooth controller recovery — 8 October 2026

The owner installed two 16 GB Timetec DDR4 modules and a USB Bluetooth adapter.
PC1 boots and reports 31 GiB of usable memory. The owner confirmed wireless
controller input and vibration, then reported Tekken's Player 1 disconnected
message with controller lights still on. PS did not open the appliance menu.

## Live observations

- Adapter: UGREEN BT6.0, USB VID/PID `33fa:0012`, Bluetooth address
  `04:7F:0E:01:5A:B1`.
- Kernel: `7.1.5-101.fc43.x86_64`; BlueZ: `5.87`.
- Two Sony DualSense controllers were routed to player slots one and two at
  20:28:39 and 20:29:03 UTC respectively.
- At 20:31:03 UTC, BlueZ logged two
  `hidp_send_message() BT socket write error: Resource temporarily unavailable (11)`
  messages. Both physical input devices disappeared; the controller broker
  received `ENODEV` and removed the two corresponding application devices.
- BlueZ continued to report both controllers paired, trusted and connected,
  despite neither controller having a kernel input device. The broker remained
  alive in its normal poll loop; no broker restart was needed.
- The configuration uses BlueZ's default userspace HID implementation.
  USB runtime power status was active when inspected; autosuspend is not
  established as the cause.

BlueZ 5.87's [`hidp_send_output`](https://github.com/bluez/bluez/blob/5.87/profiles/input/device.c#L646-L658)
destroys the UHID device if sending a Bluetooth output report fails. This is
consistent with the observed errors, missing input nodes and still-connected
Bluetooth status. The cause of the socket backpressure is not yet established;
this does not prove a defective adapter, RF interference or a memory fault.

## Recovery and limits

The two existing Bluetooth bonds were retained. The stalled links were explicitly
disconnected, then the owner pressed PS to reconnect. Player one returned at
20:34:40 UTC; the owner confirmed that this controller again navigates the menu.
Player two returned to its original slot at 20:35:10 UTC according to the broker.

The owner subsequently confirmed that both controllers control Tekken again.
No game, shell, controller broker or PC reboot was needed for that recovery.
Reconnection alone is recovery from this incident, not a demonstrated permanent
fix.

Focused software evidence: `out/bluetooth-controller-recovery-20261008.json`.

## Prevention attempt: kernel HID transport

After the owner asked how to prevent recurrence, the installed kernel's signed
`hidp` module was verified and loaded. At 20:37:11 UTC, PC1's
`/etc/bluetooth/input.conf` was changed to set `UserspaceHID=false` in `[General]`,
then only the system Bluetooth service was restarted. This intentionally
disconnects both pads once. No bonds or player-slot records were removed.

This is a supported BlueZ setting that selects the kernel HIDP implementation.
The kernel queues outgoing HID reports and retries a temporarily unavailable
socket, avoiding BlueZ's immediate UHID destruction on the observed output-send
failure. It does not establish the underlying reason for Bluetooth backpressure
or guarantee against other wireless disconnects.

The original configuration and SHA256 records are saved on PC1 at
`/var/marwanos/bluetooth-hidp-20261008/input.conf.original` and `change.json`.
To revert, restore that original file to `/etc/bluetooth/input.conf`, restart
`bluetooth.service`, and reconnect both controllers. The change is persistent
on this PC1 installation; it is not a published image change or a new general
default in the repository. The live broker reattached player one at 20:37:34 UTC
and player two at 20:39:10 UTC, retaining both slots and advertising rumble.
The post-change input inventory uses the kernel Bluetooth HID path, with two
HIDP references. The owner then reported four flickering player lights on the
first controller and confirmed that controls and PS/Home still work. The live
inventory retained both physical and application devices without another broker
disconnect at 20:40:29 UTC. Controls and Home are therefore physically confirmed
after the transport change; rumble retesting and sustained stability remain
pending.

Both controllers' kernel LED settings already represented player one (center
LED) and player two (two symmetric LEDs), with no blink trigger selected. The
same patterns were explicitly reissued through their existing sysfs brightness
controls without reconnecting either pad. The observed four-light flicker is not
explained by the kernel's requested LED pattern, and visual resolution after
the refresh was not achieved: the owner said the four dots still flickered.

The owner subsequently confirmed that the flicker stopped after restarting PC1.
Live inspection found a new boot ID `697406c6-9ec5-4328-9708-308b0b3e7f55`,
retained `UserspaceHID=false`, and player one reattached at 20:44:28 UTC through
kernel HIDP. Its battery reported 85%, its requested LED pattern was one center
dot with no blink trigger, and no process held a controller hidraw node in that
sample. The prior journal ends in an orderly shutdown. The agent did not initiate
this reboot. The owner's report establishes that restart cleared the visible
flicker; its precise cause remains unproven. Sustained two-controller gameplay
and post-change rumble retesting remain separate from that visual result.

Post-restart software evidence: `out/bluetooth-controller-flicker-20261008.json`.

Post-change software evidence: `out/bluetooth-controller-kernel-hid-20261008.json`.

References: [BlueZ input configuration](https://github.com/bluez/bluez/blob/5.87/profiles/input/input.conf),
[kernel HIDP transport](https://github.com/torvalds/linux/blob/master/net/bluetooth/hidp/core.c).
