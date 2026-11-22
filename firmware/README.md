# Firmware packages

No firmware binaries are stored in this repository.

Use:

```bash
./scripts/fetch-firmware.sh --auto
```

The script asks Garmin for the latest **live** package for the connected model,
downloads it from Garmin's `download.garmin.com` server, checks Garmin's size
and MD5, and extracts:

- `GUPDATE.GSP`
- `force.tmp`
- `gupdate.gsp.sha256`
- `version.txt` (discovered version, access level, source URL, hashes)

Without a connected watch, use `--model 006-V4585-00` (see the README table).

The `firmware/` directory contents are ignored by git (see `.gitignore`).

## Why not commit the binaries?

- They are proprietary Garmin firmware.
- They are large (~20 MB per model).
- Garmin's official URLs are the authoritative source.
- Keeping binaries out of git avoids stale or mismatched packages.

If a link expires, find the current Instinct 3 backdate/beta announcement on
the Garmin forums and use the model-specific ZIP, or obtain the package through
Garmin support. Always verify the embedded manifest and SHA-256 before
installing.
