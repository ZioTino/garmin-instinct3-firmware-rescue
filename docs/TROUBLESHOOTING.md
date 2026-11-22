# Troubleshooting

## The watch is not detected

- Use a data-capable cable and a direct USB port.
- Try the GPS-hold service mode again: power off, hold GPS, plug in, keep
  holding 30 seconds after the drive appears.
- On Linux, check `lsusb | grep -i garmin` and `gio mount -li`.
- On macOS, normal Instinct 3 MTP connections do not show in Finder. Use an MTP
  browser or a Windows machine.

## `ExtData` is not visible

You are in normal MTP mode. Eject safely, power off, and repeat the GPS-hold
procedure. The official Garmin FAQ explicitly says to repeat the step if
`ExtData` is missing.

## `cp: Operation not supported`

The gvfs MTP FUSE mount does not support normal file creation the way `cp`
expects. Use `gio copy`:

```bash
gio copy ./force.tmp 'mtp://<host>/Internal Storage/Garmin/force.tmp'
gio copy ./gupdate.gsp 'mtp://<host>/Internal Storage/Garmin/GUPDATE.GSP'
```

The helper script does this automatically.

## MTP rename fails

Some devices return `libmtp error: could not set object string` for rename.
Do not rename after copying. Delete the wrong file and copy again with the
exact uppercase destination name `GUPDATE.GSP`.

## No update prompt after unplugging

Check all of these:

1. File is exactly `GUPDATE.GSP` (uppercase), in the `Garmin` folder.
2. `force.tmp` exists in the same folder and is zero bytes.
3. The file size matches the downloaded package.
4. Free space is at least the package size plus ~1 MB.
5. The package matches the watch model/part number.
6. Power-cycle the watch while unplugged.

If the watch deleted `force.tmp` but left `GUPDATE.GSP`, the filename case was
the likely cause.

## It reboots but the version is unchanged

- Reconnect and confirm the files are still present.
- Re-check the model/package match in `GarminDevice.xml`.
- Make sure you did not copy an old `GUPDATE.GCD` or a package for another
  model.
- Re-run `clean`, then `install`, then power-cycle.

## Stuck on `Restarting...`

Wait. The verified install can take a long time. Do not reset before 30
minutes. If it is still stuck after 45–60 minutes:

1. Reconnect normally and inspect the watch.
2. Confirm whether `GUPDATE.GSP` was consumed (success) or is still present.
3. Check free space and available logs.
4. If needed, copy the package again and retry once.

Repeated hard resets during an install are riskier than waiting.

## Garmin Express still says “not enough memory”

Do not use Garmin Express for this recovery. It wants room for multiple copies.
Use the manual `GUPDATE.GSP` method.

## The watch still offers the old update over the air

After a successful manual install, connect to Garmin Connect / Wi-Fi once and
run `Check For Updates`. With 50+ MB free, the OTA path should behave normally.

## Will a factory reset undo the update?

No. Factory reset clears user data and settings, not firmware. The watch stays
on the installed version. Only a deliberate manual backdate
(`older GUPDATE.GSP` + `force.tmp`) changes it.
