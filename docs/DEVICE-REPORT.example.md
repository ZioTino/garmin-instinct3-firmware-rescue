# Device report example

Copy this template into an issue, but **remove unique identifiers**.

```text
Model (Description): Instinct 3 - 45mm, Solar
PartNumber:          006-B4585-00
SoftwareVersion:     521 (5.21)
Target package:      006-V4585-00 / 15.19
Free space before:   ~21 MB
Free space after:    ~34 MB (after cleanup)
Result:              1519 (15.19), ~58 MB free
OS used:             Linux
Connection mode:     GPS-hold mass-storage / MTP
```

Keep:

- model description
- part number (model-level, not unique)
- firmware versions
- free-space numbers
- OS and connection mode
- error text

Remove:

- device serial number
- unit ID / `<Id>` value
- USB bus/device paths
- home directory paths and usernames
- Garmin account / pairing details
- any file that contains a unique device fingerprint
