# Garmin Instinct 3 firmware rescue

Recover a Garmin Instinct 3 that is stuck on old firmware, loops on
**“Restarting…”**, or makes Garmin Express say:

> “The latest software does not fit on your device's internal memory.”

This is a manual, USB-only recovery method. It does **not** need Garmin
Express, Garmin Connect, Windows, or a phone. It clears stale update data that
Garmin normally hides, then installs an official, signed `GUPDATE.GSP`
package.

> **Verified:** Instinct 3 – 45 mm, Solar, firmware **5.21 → 15.19**.
> Free space went from ~21 MB to **58 MB**, and the update completed normally.

## Why the normal update fails

The Instinct 3 Solar has a small user-visible FAT volume. On affected units:

1. A failed or partial update leaves a large `ExtData` folder (stale fonts)
   plus `NewFiles` / `GUPDATE*` leftovers behind.
2. The next update needs roughly 20 MB. Garmin Express wants room for more
   than one copy of the package, so it reports “not enough memory”.
3. The watch's OTA path tries to unpack the update in place, hangs on
   `Restarting...`, and boots back into the old version.

The fix is to remove `ExtData` (which is ~12 MB on an affected watch) and copy
the update manually with the marker file Garmin uses for forced installs.

## What the watch expects

Read from the watch's own `Garmin/GarminDevice.xml`:

```xml
<UpdateFile>
  <PartNumber>006-V4585-00</PartNumber>
  <Version><Major>5</Major><Minor>21</Minor></Version>
  <Path>Garmin</Path>
  <FileName>GUPDATE.GSP</FileName>
</UpdateFile>
```

Two details matter:

- The file must be named **`GUPDATE.GSP`** (uppercase). A lowercase
  `gupdate.gsp` is silently ignored by the watch.
- A zero-byte **`force.tmp`** marker next to it makes the watch accept a
  manually copied package, including a different version.

The watch consumes both files during a successful install.

## Quick start (Linux)

Requirements: **Bash 4+**, `curl`, `unzip`, `gio` / `gvfs-backends`,
`udisksctl` (optional, for mass-storage mode), `sha256sum`. The helper scripts
are Linux-oriented; Windows and macOS users can follow the manual steps in
`docs/PROCEDURE.md`.

```bash
git clone https://github.com/ZioTino/garmin-instinct3-firmware-rescue.git
cd garmin-instinct3-firmware-rescue

# 1. Download the official package for your exact model
./scripts/fetch-firmware.sh --model 006-V4585-00

# 2. Connect the watch normally and confirm the model/version
./scripts/garmin-watch.sh status

# 3. Power the watch off, then connect it while holding GPS for 30 seconds
#    (see the detailed procedure below)

# 4. Clear hidden update junk and install the package
./scripts/garmin-watch.sh clean
./scripts/garmin-watch.sh install
./scripts/garmin-watch.sh unmount

# 5. Unplug, power on, accept the update prompt, wait 20-30 minutes
# 6. Reconnect and verify
./scripts/garmin-watch.sh verify
```

The scripts only touch known update paths: `ExtData`, the contents of
`NewFiles`, `GUPDATE*` / `gupdate*`, and the two files they copy. They never
delete `GarminDevice.xml`, settings, or activities by default.

## The one manual step that matters

Garmin's official service mode is entered like this:

1. Power the watch **off**.
2. Hold the **GPS** button (top-right on an Instinct 3).
3. While still holding GPS, plug the USB cable into the watch.
4. Keep holding GPS for **30 seconds after the computer sees the drive**.
5. Release GPS.

In normal MTP mode, `ExtData` is hidden. In this mode it becomes visible and
the watch behaves like a writable drive. If you do not see `ExtData`, eject
safely, power off, and repeat the GPS-hold step.

## Detailed procedure

See [docs/PROCEDURE.md](docs/PROCEDURE.md) for the full walkthrough,
including Windows/macOS notes and the exact cleanup list.

## Supported models and packages

These are the official Garmin **15.19** rescue packages published in the
Instinct 3 beta announcement. Use the package that matches the model reported
by `GarminDevice.xml`.

| Model | Package ID | `fetch-firmware.sh --model` |
|---|---|---|
| Instinct E 40 mm | `006-V4583-00` | `006-V4583-00` |
| Instinct E 45 mm | `006-V4584-00` | `006-V4584-00` |
| Instinct 3 Solar 45 mm | `006-V4585-00` | `006-V4585-00` |
| Instinct 3 AMOLED 45 mm | `006-V4586-00` | `006-V4586-00` |
| Instinct 3 AMOLED 50 mm | `006-V4587-00` | `006-V4587-00` |
| Instinct Crossover AMOLED | `006-V4678-00` | `006-V4678-00` |
| Instinct 3 Solar 50 mm | `006-V4759-00` | `006-V4759-00` |

For the 45 mm Solar, 15.19 is the current stable release at the time of
writing. Newer 16.x builds are rolling out to other Instinct 3 variants; once
the watch has healthy free space, normal OTA updates work again.

## Troubleshooting

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md). The most common ones:

| Symptom | Fix |
|---|---|
| `cp: Operation not supported` over MTP | Use `gio copy`; the script already does. |
| `ExtData` is not visible | You are in normal MTP mode. Repeat the GPS-hold procedure. |
| No update prompt after unplugging | Ensure the file is `GUPDATE.GSP` uppercase, in `Garmin/`, with `force.tmp`; power-cycle. |
| Still on old version after reboot | Re-check `force.tmp`, free space, and the package/model match. |
| Stuck on `Restarting...` | Wait up to 30 minutes; do not reset or unplug. |
| Garmin Express says “not enough memory” | Use this manual method instead. |

## Safety and disclaimer

- Manual firmware changes can brick a device. Use at your own risk.
- Keep the watch charged (above ~50 %) and never disconnect during
  `Restarting...` / progress.
- Use only the package for your exact model. The model part number is in
  `Garmin/GarminDevice.xml`.
- This project is **not affiliated with Garmin**. Garmin, Instinct, and related
  marks are trademarks of Garmin Ltd.
- Firmware binaries are **not hosted in this repository**. The fetch script
  downloads them from Garmin's official `download.garmin.com` servers, and
  verifies a SHA-256 when a known hash is available.
- A factory reset keeps the installed firmware. It only clears user data and
  settings.

## Credits

The procedure combines Garmin's official Instinct 3 support FAQ with field
reports from the Garmin forums. See [docs/SOURCES.md](docs/SOURCES.md).

## License

MIT. See [LICENSE](LICENSE).
