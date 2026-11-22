# Sources

These are the primary sources used to build and verify this method.

## Garmin official

- **Unable to Install Software Updates on an Instinct 3 or Instinct E Series
  Watch** — Garmin support FAQ. Documents the GPS-hold service mode and the
  `ExtData` / `New Files` / `Gupdate` cleanup.
  <https://support.garmin.com/en-US/?faq=PXWaNWoxEa40zkLfERZiP6>

- **Instinct 3 System Software 15.19** — Garmin release announcement.
  <https://forums.garmin.com/outdoor-recreation/outdoor-recreation/f/instinct-3/444764/instinct-3-system-software-15-19>

- **Beta Version 16.04** — contains the per-model official 15.19 backdate ZIP
  links used by `fetch-firmware.sh`.
  <https://forums.garmin.com/beta-program/instinct-3/f/announcements/444391/beta-version-16-04--check-for-updates-only>

- **Instinct 3 Solar owner's manual** — software update menu reference.
  <https://www8.garmin.com/manuals/webhelp/GUID-2C274FD2-F0C3-445C-B0AC-700FECCE12E9/EN-US/>

## Garmin forums (field reports)

- **Instinct 3 stuck at v5.21 and “Restarting...” after updates** — the exact
  symptom loop and the GPS-hold + `ExtData` fix.
  <https://forums.garmin.com/outdoor-recreation/outdoor-recreation/f/instinct-3/432973/instinct-3-stuck-at-v5-21-and-restarting-after-updates>

- **Instinct 3 update 8.09 stuck at “Restarting...”** — cleanup list and
  reset-then-update reports.
  <https://forums.garmin.com/outdoor-recreation/outdoor-recreation/f/instinct-3/406825/instinct-3-update-8-09-stuck-at-restarting>

- **[6.29 Instinct 3 Solar] The latest software does not fit on your device's
  internal memory** — Garmin staff cleanup steps and “update through Garmin
  Connect instead of Express” workaround.
  <https://forums.garmin.com/outdoor-recreation/outdoor-recreation/f/instinct-3/402959/6-29-instinct-3-solar-the-latest-software-does-not-fit-on-your-device-s-inter-memory>

- **Brand new Instinct 3 Solar software version 5.21** — two-file manual
  install reports and the “40+ MB free afterwards” result.
  <https://forums.garmin.com/outdoor-recreation/outdoor-recreation/f/instinct-3/410594/brand-new-instinct-3-solar-software-version-5-21>

- **Software downloads after 10.30 came out, but no option to install** —
  confirms `GUPDATE.gsp` is written into `GARMIN` and consumed by the watch.
  <https://forums.garmin.com/outdoor-recreation/outdoor-recreation/f/instinct-3/419952/software-downloads-after-10-30-came-out-but-no-option-to-install>

- **Chromebooks and Garmin** — background on manual firmware file placement
  (`GARMIN` folder, reboot to install).
  <https://forums.garmin.com/apps-software/mobile-apps-web/f/garmin-connect-web/84075/chromebooks-and-garmin/458197>

## Secondary

- Garmin Rumors — 15.19 stable release coverage (confirms Solar inclusion).
  <https://garminrumors.com/garmin-releases-instinct-3-series-stable-version-15-19>
- Garmin Rumors wiki — Instinct 3 software update history.
  <https://wiki.garminrumors.com/Instinct_3_Software_Updates>
  (may be Cloudflare-protected)
- DevicesFAQ — Instinct 3 factory reset steps.
  <https://www.devicesfaq.com/en/reset/garmin-instinct-3>
