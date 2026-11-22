# Detailed procedure

This walkthrough is written for an Instinct 3 Solar 45 mm on firmware 5.21,
but the same steps apply to the other Instinct 3 family models with the
matching package.

## 0. Before you start

- Charge the watch. Aim for **above 50 %**, ideally on the charger.
- Use a **data-capable** USB cable and a direct port (no hub if possible).
- Back up anything you care about. The install itself does not erase user data,
  but a factory reset or a failed install can.
- You need the package for your exact model. See the table in the README.

## 1. Identify the watch

Connect the watch normally, mount it, and open:

```
<watch>/Garmin/GarminDevice.xml
```

Look for:

```xml
<Model>
  <PartNumber>006-B4585-00</PartNumber>
  <SoftwareVersion>521</SoftwareVersion>
  <Description>Instinct 3 - 45mm, Solar</Description>
</Model>
```

`SoftwareVersion` is an integer: `521` = 5.21, `1519` = 15.19.

On Linux:

```bash
./scripts/garmin-watch.sh status
```

The script prints the model, version, free space, and any cleanup targets.

## 2. Discover and download the official package

With the watch connected (normal MTP mode is fine):

```bash
./scripts/fetch-firmware.sh --auto
```

The helper:

1. Reads the watch's `GarminDevice.xml`.
2. Sends a **sanitized** copy to Garmin's update service
   (`SoftwareUpdateService/GetAllUnitSoftwareUpdates`) — the same service
   Garmin Express uses.
3. Requests the **live** channel and selects the system bundle
   (`GUPDATE.GSP` / `GUPDATE.GCD`).
4. Downloads it from Garmin's `download.garmin.com` server, checks the size and
   MD5 that Garmin reports, extracts `gupdate.gsp` + `force.tmp`, and writes
   `version.txt` and a SHA-256 file.

No personal identifiers are sent: the unit id is replaced with a neutral value
(`1`), and `<Extensions>` / `<DataType>` are stripped.

If no watch is connected, ask for a specific model:

```bash
./scripts/fetch-firmware.sh --model 006-V4585-00
```

If Garmin answers with a beta/alpha access level, the script stops. Pass
`--allow-nonlive` only if you deliberately want that build.

If the service changes or is unreachable, use a direct official URL:

```bash
./scripts/fetch-firmware.sh --url 'https://download.garmin.com/gsup/.../gupdate.gsp' \
  --slug instinct3-solar-45 --version 15.19
```

The link may be a raw `.gsp` or a ZIP containing `gupdate.gsp` and `force.tmp`.
Verify the embedded manifest references your model/package part number:

```bash
strings firmware/extracted/instinct3-solar-45/gupdate.gsp \
  | grep -o 'manifest.xml.*' | head -c 1000
```

## 3. Enter Garmin's mass-storage service mode

This is the key step. In normal MTP mode, `ExtData` is hidden.

1. Unplug the cable.
2. Power the watch off.
3. Press and **hold the GPS button** (top-right on an Instinct 3).
4. While still holding GPS, plug the USB cable into the watch.
5. Wait until the computer sees the drive, then **keep holding GPS for another
   30 seconds**.
6. Release GPS.

### Linux

The watch may appear as an MTP volume or as a block device, depending on model
and firmware. The helper handles both:

```bash
./scripts/garmin-watch.sh mount
```

If it is a block device and does not auto-mount:

```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL,MODEL
udisksctl mount -b /dev/sdXN
```

### Windows

Open **This PC** and wait for the Garmin drive. The official FAQ uses this
exact mode.

### macOS

Normal Instinct 3 connections are MTP and do not appear as a drive in Finder.
Use a tool that speaks MTP, or follow Garmin's official FAQ from a Windows
machine. The core file operations are the same.

## 4. Clean hidden update junk

Delete, inside the watch's `Garmin` folder:

- `ExtData/` — the big one, often ~12 MB of stale fonts
- contents of `NewFiles/`
- any `GUPDATE*` / `gupdate*` file

On Linux the helper does this:

```bash
./scripts/garmin-watch.sh clean
```

Optional extra cleanup if space is still tight:

```bash
./scripts/garmin-watch.sh clean --extra
```

That also empties `RemoteSW`, `DEBUG`, `SUMMARY`, `Sports`, `FbtBackup`,
`FbtPtdBackup`, and `TempFIT`. It does not touch settings, activities, maps,
or `GarminDevice.xml`.

Check the result:

```bash
df -h <watch-root>
```

You want at least the package size plus a small margin. On the verified
45 mm Solar, free space went from ~21 MB to ~34 MB after cleanup.

## 5. Copy the update

The package must end up as:

```
<watch>/Garmin/GUPDATE.GSP
<watch>/Garmin/force.tmp
```

The helper does the copy and verifies the SHA-256:

```bash
./scripts/garmin-watch.sh install
```

Why the script exists:

- Over gvfs MTP, plain `cp` fails with `Operation not supported`. `gio copy`
  works.
- MTP cannot rename objects on all devices, so the script copies directly to
  the uppercase name `GUPDATE.GSP`.
- A lowercase `gupdate.gsp` is ignored by the watch.

If you copy manually on Windows, just name the file `GUPDATE.GSP` and create an
empty file named `force.tmp` in the same folder.

## 6. Install

1. Safely unmount/eject.
2. Unplug the watch.
3. Power it on (hold the top-left LIGHT/CTRL button).
4. The watch should detect the package and show an update prompt. Accept it.
   On some firmware it starts automatically.
5. It will sit on `Restarting...` or a progress display for a long time —
   **up to 20–30 minutes**.
6. Do not press buttons, reset, or reconnect during this phase.

When it finishes, it reboots to the watch face.

## 7. Verify

On the watch:

```
Menu -> System -> About -> Software Version
```

Or reconnect normally and run:

```bash
./scripts/garmin-watch.sh verify
```

Expected result for the verified case:

```
SoftwareVersion 1519  (15.19)
```

Also check free space. The verified watch went from ~21 MB free to **58 MB**
free, because the old `ExtData` was gone and the update package was consumed.

## 8. Afterwards

- Check `Menu -> System -> Software Update -> Check For Updates` once. With
  healthy free space, normal OTA updates should work again.
- A factory reset keeps the installed firmware. It only wipes user data and
  settings.
- To intentionally go back to an older build, you would need an older
  `GUPDATE.GSP` plus `force.tmp`; a normal reset will not downgrade.
