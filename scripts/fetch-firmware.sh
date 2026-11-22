#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Discover the latest LIVE system software for an Instinct 3 model from Garmin's
# update service, download it, and extract GUPDATE.GSP + force.tmp.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
FW_ROOT="${FW_ROOT:-$REPO_DIR/firmware}"

MODEL=""
AUTO=0
XML=""
URL=""
SLUG=""
VERSION_LABEL=""
ALLOW_NONLIVE=0
LIST=0

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*" >&2; }
warn() { echo "WARNING: $*" >&2; }

usage() {
  cat <<'EOF'
Usage: fetch-firmware.sh [options]

By default, with the watch connected in normal MTP mode, the script reads its
GarminDevice.xml and asks Garmin for the latest LIVE system software.

Options:
  --auto                 Read the model from the connected watch (default)
  --model ID             Package id, e.g. 006-V4585-00, when no watch is connected
  --xml FILE             Use a specific GarminDevice.xml
  --url URL              Skip discovery and download this official URL
  --slug NAME            Output directory name (with --url)
  --version LABEL        Version label (with --url)
  --allow-nonlive        Accept beta/alpha offers (default: live only)
  --list                 List known model/package ids
  --help                 Show this help

Environment:
  FW_ROOT                Download/extract root (default: <repo>/firmware)
  MTP_URI                Override MTP URI for auto-detection
  WATCH_ROOT             Use an already-mounted watch path
EOF
}

# label | slug | device part (package part is the key)
declare -A PKG=(
  [006-V4583-00]="Instinct E 40 mm|instinct-e-40|006-B4583-00"
  [006-V4584-00]="Instinct E 45 mm|instinct-e-45|006-B4584-00"
  [006-V4585-00]="Instinct 3 Solar 45 mm|instinct3-solar-45|006-B4585-00"
  [006-V4586-00]="Instinct 3 AMOLED 45 mm|instinct3-amoled-45|006-B4586-00"
  [006-V4587-00]="Instinct 3 AMOLED 50 mm|instinct3-amoled-50|006-B4587-00"
  [006-V4678-00]="Instinct Crossover AMOLED|instinct-crossover-amoled|006-B4678-00"
  [006-V4759-00]="Instinct 3 Solar 50 mm|instinct3-solar-50|006-B4759-00"
)

print_list() {
  printf '%-16s  %-28s  %s\n' "PACKAGE ID" "MODEL" "SLUG"
  local id rest label slug dev
  for id in "${!PKG[@]}"; do
    rest="${PKG[$id]}"
    IFS='|' read -r label slug dev <<< "$rest"
    printf '%-16s  %-28s  %s\n' "$id" "$label" "$slug"
  done | sort
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) [[ $# -ge 2 ]] || die "--model needs an id"; MODEL="$2"; shift 2 ;;
    --auto) AUTO=1; shift ;;
    --xml) [[ $# -ge 2 ]] || die "--xml needs a file"; XML="$2"; shift 2 ;;
    --url) [[ $# -ge 2 ]] || die "--url needs a URL"; URL="$2"; shift 2 ;;
    --slug) [[ $# -ge 2 ]] || die "--slug needs a name"; SLUG="$2"; shift 2 ;;
    --version) [[ $# -ge 2 ]] || die "--version needs a label"; VERSION_LABEL="$2"; shift 2 ;;
    --allow-nonlive) ALLOW_NONLIVE=1; shift ;;
    --list) LIST=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

if [[ "$LIST" == "1" ]]; then
  print_list
  exit 0
fi

command -v curl >/dev/null 2>&1 || die "curl is required"
command -v python3 >/dev/null 2>&1 || die "python3 is required"
command -v md5sum >/dev/null 2>&1 || die "md5sum is required"

JSON_TMP="$(mktemp)"
trap 'rm -f "$JSON_TMP"' EXIT

if [[ -n "$URL" ]]; then
  SLUG="${SLUG:-manual}"
  VERSION_LABEL="${VERSION_LABEL:-manual}"
  ACCESS="manual"
  PACKAGE_PART="manual"
  MD5=""
  SIZE=""
  DISPLAY="manual download"
  LABEL="manual download"
  REINSTALL=0
else
  DISCOVER_ARGS=()
  if [[ -n "$XML" ]]; then
    [[ -f "$XML" ]] || die "XML file not found: $XML"
    DISCOVER_ARGS=(--xml "$XML")
  elif [[ -n "$MODEL" ]]; then
    MODEL="${MODEL^^}"
    [[ "$MODEL" == 006-B* ]] && MODEL="${MODEL/006-B/006-V}"
    [[ -n "${PKG[$MODEL]:-}" ]] || die "Unknown package id '$MODEL'. Use --list."
    DISCOVER_ARGS=(--model "$MODEL")
  else
    AUTO=1
    ROOT="$("$SCRIPT_DIR/garmin-watch.sh" mount)" \
      || die "Could not find a connected watch. Use --model ID or --xml FILE."
    XML="$ROOT/Garmin/GarminDevice.xml"
    [[ -f "$XML" ]] || XML="$ROOT/GARMIN/GarminDevice.xml"
    [[ -f "$XML" ]] || die "GarminDevice.xml not found under the watch root"
    DISCOVER_ARGS=(--xml "$XML")
  fi

  if [[ "$ALLOW_NONLIVE" == "0" ]]; then
    DISCOVER_ARGS+=(--require-live)
  fi

  info "Asking Garmin for the latest live system software..."
  python3 "$SCRIPT_DIR/discover-firmware.py" "${DISCOVER_ARGS[@]}" > "$JSON_TMP"

  eval "$(python3 - "$JSON_TMP" <<'PY'
import json, shlex, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
for key, value in (
    ("PACKAGE_PART", d.get("packagePartNumber") or ""),
    ("VERSION_LABEL", d.get("version") or ""),
    ("URL", d.get("url") or ""),
    ("MD5", d.get("md5") or ""),
    ("SIZE", "" if d.get("size") is None else str(d.get("size"))),
    ("ACCESS", d.get("accessLevel") or ""),
    ("DISPLAY", d.get("displayName") or ""),
    ("REINSTALL", "1" if d.get("isReinstall") else "0"),
):
    print(f"{key}={shlex.quote(str(value))}")
PY
)"

  [[ -n "$URL" ]] || die "Garmin did not return a download URL"
  [[ -n "$PACKAGE_PART" ]] || die "Garmin did not return a package part number"
  [[ -n "$VERSION_LABEL" ]] || die "Garmin did not return a version"

  if [[ -z "$SLUG" ]]; then
    for id in "${!PKG[@]}"; do
      if [[ "$id" == "$PACKAGE_PART" ]]; then
        IFS='|' read -r LABEL SLUG _dev <<< "${PKG[$id]}"
        break
      fi
    done
  fi
  [[ -n "${SLUG:-}" ]] || SLUG="model-${PACKAGE_PART//[^A-Za-z0-9._-]/_}"
  [[ -n "${LABEL:-}" ]] || LABEL="$PACKAGE_PART"
fi

mkdir -p "$FW_ROOT/downloads" "$FW_ROOT/extracted"
OUT="$FW_ROOT/extracted/$SLUG"
SAFE_VERSION="${VERSION_LABEL//[^A-Za-z0-9._-]/_}"
BASE_EXT="${URL%%\?*}"
BASE_EXT="${BASE_EXT##*.}"
case "${BASE_EXT,,}" in
  zip|gsp|gcd) EXT="${BASE_EXT,,}" ;;
  *) EXT="bin" ;;
esac
DL="$FW_ROOT/downloads/${SLUG}-${SAFE_VERSION}.${EXT}"

info "Model:   ${LABEL:-$PACKAGE_PART}"
info "Version: $VERSION_LABEL (access: $ACCESS)"
if [[ "${REINSTALL:-0}" == "1" ]]; then
  info "Garmin flags this as a reinstall (the watch may already be on this version)"
fi
info "Source:  $URL"
info "File:    ${DL#"$REPO_DIR"/}"

if [[ -f "$DL" ]]; then
  info "Using existing download (delete it to re-download)"
else
  CURL_URL="${URL// /%20}"
  curl -fL --retry 3 --progress-bar -o "$DL" "$CURL_URL"
fi

ACTUAL_SIZE="$(stat -c %s "$DL")"
if [[ -n "$SIZE" && "$ACTUAL_SIZE" != "$SIZE" ]]; then
  rm -f "$DL"
  die "Downloaded size $ACTUAL_SIZE does not match Garmin's $SIZE; deleted the file"
fi

if [[ -n "$MD5" ]]; then
  ACTUAL_MD5="$(md5sum "$DL" | awk '{print $1}')"
  if [[ "$ACTUAL_MD5" != "$MD5" ]]; then
    rm -f "$DL"
    die "MD5 mismatch (got $ACTUAL_MD5, expected $MD5); deleted the file"
  fi
  info "MD5 verified: $ACTUAL_MD5"
fi

rm -rf "$OUT"
mkdir -p "$OUT"

if [[ "$EXT" == "zip" ]] || file "$DL" | grep -qi 'zip archive'; then
  TMP="$FW_ROOT/extracted/.tmp-$SLUG"
  rm -rf "$TMP"
  mkdir -p "$TMP"
  unzip -tq "$DL" >/dev/null || die "Downloaded ZIP is corrupt: $DL"
  unzip -q -o "$DL" -d "$TMP"
  SRC_GSP="$(find "$TMP" -iname 'gupdate.gsp' -print -quit)"
  SRC_FORCE="$(find "$TMP" -iname 'force.tmp' -print -quit)"
  [[ -n "$SRC_GSP" ]] || die "gupdate.gsp not found inside $DL"
  cp -f "$SRC_GSP" "$OUT/gupdate.gsp"
  if [[ -n "$SRC_FORCE" ]]; then
    cp -f "$SRC_FORCE" "$OUT/force.tmp"
  else
    : > "$OUT/force.tmp"
  fi
  rm -rf "$TMP"
elif [[ "$EXT" == "gsp" ]]; then
  cp -f "$DL" "$OUT/gupdate.gsp"
  : > "$OUT/force.tmp"
elif [[ "$EXT" == "gcd" ]]; then
  die "This package is GUPDATE.GCD. This guide targets Instinct 3 GUPDATE.GSP packages."
else
  die "Unrecognized package format: $DL"
fi

SHA="$(sha256sum "$OUT/gupdate.gsp" | awk '{print $1}')"
printf '%s  gupdate.gsp\n' "$SHA" > "$OUT/gupdate.gsp.sha256"

cat > "$OUT/version.txt" <<EOF
package=${PACKAGE_PART}
version=${VERSION_LABEL}
access=${ACCESS}
source=${URL}
md5=${MD5}
sha256=${SHA}
display=${DISPLAY}
fetched=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

info "Extracted to: ${OUT#"$REPO_DIR"/}"
stat -c 'gupdate.gsp: %s bytes' "$OUT/gupdate.gsp"
echo "sha256: $SHA"
echo
info "Install with: ./scripts/garmin-watch.sh install --package \"${OUT#"$REPO_DIR"/}\""
