#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Download an official Garmin Instinct 3 rescue package (15.19) for an exact
# model, extract GUPDATE.GSP + force.tmp, and write a SHA-256 file.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
FW_ROOT="${FW_ROOT:-$REPO_DIR/firmware}"

MODEL=""
LIST=0
AUTO=0

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }

usage() {
  cat <<'EOF'
Usage: fetch-firmware.sh --model <package-id> [--list]
       fetch-firmware.sh --auto

Options:
  --model ID   Package id, e.g. 006-V4585-00 (Instinct 3 Solar 45 mm)
  --auto       Read the model from the connected watch (normal MTP mode)
  --list       List known models and package ids
  --help       Show this help

Environment:
  FW_ROOT      Download/extract root (default: <repo>/firmware)
EOF
}

declare -A PKG=(
  [006-V4583-00]="Instinct E 40 mm|instinct-e-40|https://download.garmin.com/gsup/006-V4583-00/15.19/full/rel/9256fff8-5075-4d9c-9602-db47c83aef5e/IE%2040%20-%2015.19%20backdate.zip"
  [006-V4584-00]="Instinct E 45 mm|instinct-e-45|https://download.garmin.com/gsup/006-V4584-00/15.19/full/rel/0b1a27be-0598-448f-b979-1204a2e87cd4/IE%2045%20-%2015.19%20backdate.zip"
  [006-V4585-00]="Instinct 3 Solar 45 mm|instinct3-solar-45|https://download.garmin.com/gsup/006-V4585-00/15.19/full/rel/50bcd893-abfc-4314-a2d6-37ade3b5def4/I3%20Solar%2045%20-%2015.19%20backdate.zip"
  [006-V4586-00]="Instinct 3 AMOLED 45 mm|instinct3-amoled-45|https://download.garmin.com/gsup/006-V4586-00/15.19/full/rel/94826927-ffaf-441b-97d8-03f61da03e79/I3%20AMOLED%2045%20-%2015.19%20backdate.zip"
  [006-V4587-00]="Instinct 3 AMOLED 50 mm|instinct3-amoled-50|https://download.garmin.com/gsup/006-V4587-00/15.19/full/rel/f99029e0-3141-4179-b830-0dc48c44ca71/I3%20AMOLED%2050%20-%2015.19%20backdate.zip"
  [006-V4678-00]="Instinct Crossover AMOLED|instinct-crossover-amoled|https://download.garmin.com/gsup/006-V4678-00/15.19/full/rel/6e8c231c-29fd-49f4-bbea-5a6240fc42ba/Crossover%20AMOLED%20-%2015.19%20backdate.zip"
  [006-V4759-00]="Instinct 3 Solar 50 mm|instinct3-solar-50|https://download.garmin.com/gsup/006-V4759-00/15.19/full/rel/623ac636-dcf9-4f1c-87bc-258f50b778ca/I3%20Solar%2050%20-%2015.19%20backdate.zip"
)

declare -A KNOWN_SHA=(
  [006-V4585-00]="37e2ff741f61b7410d41022ec4c24c381ca4d2ba0911ae7be6da1fd502957cd8"
)

print_list() {
  printf '%-16s  %-28s  %s\n' "PACKAGE ID" "MODEL" "SLUG"
  local id rest label slug url
  for id in "${!PKG[@]}"; do
    rest="${PKG[$id]}"
    IFS='|' read -r label slug url <<< "$rest"
    printf '%-16s  %-28s  %s\n' "$id" "$label" "$slug"
  done | sort
}

detect_model() {
  local root xml part desc candidate
  root="$("$SCRIPT_DIR/garmin-watch.sh" mount)" || die "Could not find a connected watch"
  xml="$root/Garmin/GarminDevice.xml"
  [[ -f "$xml" ]] || xml="$root/GARMIN/GarminDevice.xml"
  [[ -f "$xml" ]] || die "GarminDevice.xml not found under $root"

  part="$(grep -oE '<PartNumber>[^<]*' "$xml" | head -1 | sed 's/<[^>]*>//')"
  desc="$(grep -oE '<Description>[^<]*' "$xml" | head -1 | sed 's/<[^>]*>//')"

  # Most Instinct 3 package ids are the device id with B -> V.
  candidate="${part/006-B/006-V}"
  if [[ -n "${PKG[$candidate]:-}" ]]; then
    printf '%s\n' "$candidate"
    return
  fi

  case "$desc" in
    *Crossover*)                    printf '006-V4678-00\n' ;;
    *"Instinct E"*40*)              printf '006-V4583-00\n' ;;
    *"Instinct E"*45*)              printf '006-V4584-00\n' ;;
    *"Instinct 3"*45*Solar*)        printf '006-V4585-00\n' ;;
    *"Instinct 3"*50*Solar*)        printf '006-V4759-00\n' ;;
    *"Instinct 3"*45*AMOLED*)       printf '006-V4586-00\n' ;;
    *"Instinct 3"*50*AMOLED*)       printf '006-V4587-00\n' ;;
    *) die "Unrecognized model: '${desc:-unknown}' (part ${part:-unknown}); use --model ID" ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) [[ $# -ge 2 ]] || die "--model needs an id"; MODEL="$2"; shift 2 ;;
    --auto)  AUTO=1; shift ;;
    --list)  LIST=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

if [[ "$LIST" == "1" ]]; then
  print_list
  exit 0
fi

if [[ "$AUTO" == "1" && -z "$MODEL" ]]; then
  MODEL="$(detect_model)"
fi

[[ -n "$MODEL" ]] || { usage; die "Specify --model ID or --auto"; }
[[ -n "${PKG[$MODEL]:-}" ]] || die "Unknown package id '$MODEL'. Use --list."

IFS='|' read -r LABEL SLUG URL <<< "${PKG[$MODEL]}"

mkdir -p "$FW_ROOT/downloads" "$FW_ROOT/extracted"
ZIP="$FW_ROOT/downloads/${SLUG}-15.19.zip"
OUT="$FW_ROOT/extracted/$SLUG"

info "Model:   $LABEL ($MODEL)"
info "Source:  $URL"
info "ZIP:     ${ZIP#"$REPO_DIR"/}"

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v unzip >/dev/null 2>&1 || die "unzip is required"

if [[ -f "$ZIP" ]]; then
  info "Using existing download (delete it to re-download)"
else
  curl -fL --retry 3 --progress-bar -o "$ZIP" "$URL"
fi

unzip -tq "$ZIP" >/dev/null || die "Downloaded ZIP is corrupt: $ZIP"

TMP="$FW_ROOT/extracted/.tmp-$SLUG"
rm -rf "$TMP" "$OUT"
mkdir -p "$TMP" "$OUT"
unzip -q -o "$ZIP" -d "$TMP"

SRC_GSP="$(find "$TMP" -iname 'gupdate.gsp' -print -quit)"
SRC_FORCE="$(find "$TMP" -iname 'force.tmp' -print -quit)"
[[ -n "$SRC_GSP" ]] || die "gupdate.gsp not found inside $ZIP"
[[ -n "$SRC_FORCE" ]] || die "force.tmp not found inside $ZIP"

cp -f "$SRC_GSP" "$OUT/gupdate.gsp"
cp -f "$SRC_FORCE" "$OUT/force.tmp"
SHA="$(sha256sum "$OUT/gupdate.gsp" | awk '{print $1}')"
printf '%s  gupdate.gsp\n' "$SHA" > "$OUT/gupdate.gsp.sha256"
rm -rf "$TMP"

if [[ -n "${KNOWN_SHA[$MODEL]:-}" && "$SHA" != "${KNOWN_SHA[$MODEL]}" ]]; then
  die "SHA-256 mismatch for $MODEL: got $SHA"
fi

info "Extracted to: ${OUT#"$REPO_DIR"/}"
stat -c 'gupdate.gsp: %s bytes' "$OUT/gupdate.gsp"
echo "sha256: $SHA"

if [[ -n "${KNOWN_SHA[$MODEL]:-}" ]]; then
  info "SHA-256 matches the known-good value for this model"
else
  info "No known-good hash for this model; recorded the computed hash"
fi

echo
info "Install with: ./scripts/garmin-watch.sh install --package \"${OUT#"$REPO_DIR"/}\""
