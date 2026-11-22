# Contributing

Thanks for helping other people recover their watches.

## Good bug reports

Please include:

- Watch model exactly as shown in `GarminDevice.xml`
  (`<Description>`), for example `Instinct 3 - 45mm, Solar`
- Model/package part number (`<PartNumber>`), for example `006-B4585-00`
- Current firmware version and the version you tried to install
- Free space reported before/after
- What step failed and the exact error text

## Privacy

**Redact unique identifiers before posting:**

- device serial number
- unit ID / `<Id>` value
- USB bus/device paths
- home directory paths and usernames
- any Garmin account or pairing details

Model and part numbers are not unique and are useful, so keep those.

## Firmware files

Do not open pull requests that add `*.gsp`, `*.gcd`, `*.rgn`, or vendor
firmware archives. The repository links to Garmin's official download servers
instead. This keeps the repository small and avoids redistributing proprietary
firmware.

## Pull requests

- Keep shell scripts POSIX-friendly where practical, but `bash` is fine.
- Run `bash -n scripts/*.sh` and `python3 -m py_compile scripts/*.py`
  before submitting.
- Never commit a real device report with personal identifiers.
