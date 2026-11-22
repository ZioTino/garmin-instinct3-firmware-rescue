# Garmin Instinct 3 firmware rescue

Recover a Garmin Instinct 3 that is stuck on old firmware, loops on
**“Restarting…”**, or makes Garmin Express say:

> “The latest software does not fit on your device's internal memory.”

This is a manual, USB-only recovery method. It does **not** need Garmin
Express, Garmin Connect, Windows, or a phone. It clears stale update data that
Garmin normally hides, then installs an official, signed `GUPDATE.GSP`
package.

The download helper **asks Garmin for the latest live version for your exact
model** instead of pinning a firmware release. At the time of writing it finds
15.19 for the Solar/E models and 16.12 for the AMOLED/Crossover models.

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

## How version discovery works

`scripts/fetch-firmware.sh` reads the watch's `GarminDevice.xml` and posts a
sanitized copy to Garmin's update service
(`SoftwareUpdateService/GetAllUnitSoftwareUpdates`), the same service Garmin
Express uses. Garmin answers with the current update options, including a
signed `GUPDATE.GSP` system bundle, its version, size, MD5, and download URL.

Privacy details:

- The unit id is replaced with a neutral value (`1`).
- `<Extensions>` and `<DataType>` elements are removed.
- No serial number, account, or real unit id is sent.

The script requests the **live** channel by default. If Garmin answers with a
beta/alpha access level, it stops instead of installing it; pass
`--allow-nonlive` only if that is intentional. It also warns if the live
version is older than the version installed on the watch (for example while
running a beta). If the service changes or is unreachable, `--model`, `--xml`,
and `--url` provide fallbacks.

## Quick start (Linux)

Requirements: **Bash 4+**, `curl`, `unzip`, `python3`, `gio` /
`gvfs-backends`, `udisksctl` (optional, for mass-storage mode), `md5sum`,
`sha256sum`. The helper scripts are Linux-oriented; Windows and macOS users
can follow the manual steps in `docs/PROCEDURE.md`.

```bash
git clone https://github.com/ZioTino/garmin-instinct3-firmware-rescue.git
cd garmin-instinct3-firmware-rescue

# 1. Connect the watch normally and confirm the model/version
./scripts/garmin-watch.sh status

# 2. Discover and download the latest live package for this watch
./scripts/fetch-firmware.sh --auto

#    No watch connected? Ask for a model instead:
#    ./scripts/fetch-firmware.sh --model 006-V4585-00

# 3. Power the watch off, then connect it while holding GPS for 30 seconds
#    (see the detailed procedure below)

# 4. Clear hidden update junk and install the discovered package
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

## Supported models

Package IDs identify the model. The script discovers the current live version
at runtime, so the table does not pin a release.

| Model | Package ID | `fetch-firmware.sh --model` |
|---|---|---|
| Instinct E 40 mm | `006-V4583-00` | `006-V4583-00` |
| Instinct E 45 mm | `006-V4584-00` | `006-V4584-00` |
| Instinct 3 Solar 45 mm | `006-V4585-00` | `006-V4585-00` |
| Instinct 3 AMOLED 45 mm | `006-V4586-00` | `006-V4586-00` |
| Instinct 3 AMOLED 50 mm | `006-V4587-00` | `006-V4587-00` |
| Instinct Crossover AMOLED | `006-V4678-00` | `006-V4678-00` |
| Instinct 3 Solar 50 mm | `006-V4759-00` | `006-V4759-00` |

At the time of writing, live versions were **15.19** for the Solar/E models
and **16.12** for the AMOLED/Crossover models. Once the watch has healthy free
space, normal OTA updates work again.

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
| `fetch-firmware.sh` cannot reach Garmin | Retry; then use `--model ID` or a direct `--url` from a Garmin announcement. |
| Garmin offers a beta/alpha build | The script refuses unless you pass `--allow-nonlive`. |
| Garmin flags a reinstall | The watch is already on that version; installing again is unnecessary. |
| Live build is older than installed | You are probably on a beta. The script warns; do not downgrade unless intended. |
| Download size or MD5 mismatch | Delete `firmware/downloads/` and retry; never install an unverified file. |

## Safety and disclaimer

- Manual firmware changes can brick a device. Use at your own risk.
- Keep the watch charged (above ~50 %) and never disconnect during
  `Restarting...` / progress.
- Use only the package for your exact model. The model part number is in
  `Garmin/GarminDevice.xml`.
- This project is **not affiliated with Garmin**. Garmin, Instinct, and related
  marks are trademarks of Garmin Ltd.
- Firmware binaries are **not hosted in this repository**. The fetch script
  downloads them from Garmin's official `download.garmin.com` servers, checks
  the MD5 and size Garmin reports, and records a SHA-256 of the extracted
  `GUPDATE.GSP`.
- Version discovery sends only the model, current version, and update-file
  list. It uses a neutral unit id and strips `<Extensions>` / `<DataType>`.
- A factory reset keeps the installed firmware. It only clears user data and
  settings.

## Credits

The procedure combines Garmin's official Instinct 3 support FAQ with field
reports from the Garmin forums. The JSON update-service request shape was
cross-checked against the open-source
[GarminServerLess](https://github.com/abadiet/GarminServerLess) and
[openExpress](https://github.com/TomaszBojanowski/openExpress) projects.
See [docs/SOURCES.md](docs/SOURCES.md).

## License

MIT. See [LICENSE](LICENSE).
