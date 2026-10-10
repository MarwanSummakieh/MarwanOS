# Controller battery tracking — 10 October 2026

PC1's Player 1 DualSense reported **5%, Charging**, over USB during this
investigation. Before USB connection, its Bluetooth input briefly reappeared
and disappeared again. This establishes a low battery reading, but does not
prove the cause of every disconnect or establish battery health. Player 2 was
disconnected and had no available battery reading.

The update is installed on PC1 at `192.168.50.206` and included in source for
future image builds. It is a persistent local bench update, not a published OS
image.

## Behavior

- The existing Bluetooth helper samples battery reports every 500 ms. It reads
  Sony's kernel power-supply attributes, matched by controller address, with
  BlueZ `Battery1.Percentage` as a fallback for connected devices.
- Paired controllers retain their remembered player numbers. USB charging is
  identified independently of Bluetooth connection status.
- The system-menu status corner shows each available battery percentage. `+`
  means charging. Settings → Bluetooth shows the percentage, charging state,
  and USB connection when applicable.
- Disconnected devices show an explicitly dated **Last battery** value in the
  Bluetooth screen. Missing/invalid reports are unavailable, never interpreted
  as zero. Initial kernel reports with unknown status are ignored.
- The existing notification inbox receives warnings at or below 20% and 10%,
  once per threshold. Charging or recovery above 25% rearms warnings. Unknown
  and disconnected readings do not generate low-battery alerts.
- Last readings survive helper restarts. A bounded history retains the last
  512 battery/connection changes; unchanged readings are checkpointed at most
  once a minute. History is stored at
  `/home/player/.local/state/marwanos/controller/battery-history.json`.

Kernel percentages are device estimates. The DualSense driver reports in
coarse increments; they cannot establish remaining runtime or battery wear.
References: [Linux power supply class](https://www.kernel.org/doc/html/latest/power/power_supply_class.html),
[DualSense driver battery decoding](https://kernel.googlesource.com/pub/scm/linux/kernel/git/joel/bmc/+/refs/tags/v6.11/drivers/hid/hid-playstation.c),
[BlueZ Battery API](https://github.com/bluez/bluez/blob/master/doc/org.bluez.Battery.rst).

## Verification and rollback

All **21 Bluetooth backend tests** pass on PC1, including the private D-Bus
agent integration and six battery regressions covering missing reports,
charging, warning thresholds, per-device isolation, bounded history, USB
transport, and saved readings after disconnect/helper restart. The focused
Godot controller/battery UI checks report zero failures. The exported shell
passes isolated startup and the controller screen was rendered under Xvfb.
The native engine is unchanged after normalizing the embedded-pack ELF metadata.

The live service publishes fresh battery state and the running shell heartbeat
remains fresh after deployment. Final shell SHA-256:
`6a08bd8796cbb1e1871ed47ad15fc963e7daba1d6129e8a6d5d979a088963ef0`.

Evidence is in `out/controller-battery-20261010/`: `deployment.json`,
`battery-backend.log`, `battery-shell.log` and the isolated UI preview. The
preview's second-controller last reading is fixture data, not a physical
measurement. Build source and logs remain in
`/var/tmp/pc1-controller-battery-20261010/` on PC1.

The helper runs from `/var/marwanos/controller-battery-20261010/manager.py`
through the player's `marwanos-bluetooth.service.d/battery.conf` override.
Rollback: remove that specific override, reload the player's systemd user
manager, and restart `marwanos-bluetooth.service`; the image-owned helper is
unchanged. Restore the saved
`/var/marwanos/controller-battery-20261010/marwanos-shell.before-battery` to
`/var/marwanos/console-design-20261009/marwanos-shell` and restart only the shell
to revert the UI. Bluetooth bonds and remembered player slots are unchanged.
