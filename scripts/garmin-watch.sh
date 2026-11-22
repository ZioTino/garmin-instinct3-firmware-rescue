#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
#
# Inspect, clean, and update a Garmin Instinct 3 over USB.
# Linux-oriented: uses gio/gvfs for MTP and udisksctl for block devices.
set -euo pipefail
shopt -s nullglob

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
PACKAGE_DIR="${PACKAGE_DIR:-$REPO_DIR/firmware/extracted}"

MTP_URI="${MTP_URI:-}"
WATCH_KIND=""
WATCH_ROOT_OVERRIDE="${WATCH_ROOT_OVERRIDE:-${WATCH_ROOT:-}}"
WATCH_ROOT=""
GARMIN_DIR=""

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*" >&2; }
warn() { echo "WARNING: $*" >&2; }

usage() {
  cat <<'EOF'
Usage: garmin-watch.sh <command> [options]

Commands:
  status                 Show model, firmware, free space and cleanup targets
  mount                  Mount/detect the watch and print its root path
  clean [--extra]        Delete ExtData, NewFiles contents and GUPDATE leftovers
  install [--package DIR] Copy force.tmp + GUPDATE.GSP and verify the checksum
  unmount                Safely unmount the watch
  verify                 Print the installed firmware version

Environment:
  MTP_URI        Override MTP URI, e.g. mtp://<host>/
  PACKAGE_DIR    Directory containing extracted package folders
  WATCH_ROOT     Use an already-mounted watch path instead of auto-detecting

The watch must be in Garmin's GPS-hold mass-storage service mode for ExtData
to be visible. Normal MTP mode hides it.
EOF
}

url_decode() {
  local s="$1"
  printf '%b' "${s//%/\\x}"
}

mtp_root_for_uri() {
  local uri="$1" host
  host="${uri#mtp://}"
  host="${host%%/*}"
  printf '/run/user/%s/gvfs/mtp:host=%s\n' "$(id -u)" "$(url_decode "$host")"
}

discover_mtp_uri() {
  if [[ -n "$MTP_URI" ]]; then
    printf '%s\n' "$MTP_URI"
    return 0
  fi

  local uri
  # Prefer a Garmin USB device (vendor 091e), then fall back to any MTP mount.
  uri="$(gio mount -li 2>/dev/null | awk '
    /^[[:space:]]*unix-device:/ { dev=$0 }
    /activation_root=mtp:\/\// {
      if (dev ~ /091e/) {
        sub(/^.*activation_root=/, "")
        print
        exit
      }
    }')"

  if [[ -z "$uri" ]]; then
    uri="$(gio mount -li 2>/dev/null \
      | sed -n 's/.*activation_root=\(mtp:\/\/[^ ]*\).*/\1/p' \
      | head -1)"
  fi

  [[ -n "$uri" ]] || return 1
  printf '%s\n' "$uri"
}

ensure_mtp_mounted() {
  local uri root
  uri="$(discover_mtp_uri)" || die "No Garmin MTP device found. Connect the watch, or set MTP_URI."
  gio mount "$uri" >/dev/null 2>&1 || true
  root="$(mtp_root_for_uri "$uri")"
  [[ -d "$root" ]] || die "MTP mount not found at $root"
  MTP_URI="$uri"
  WATCH_KIND="mtp"
  WATCH_ROOT="$root"
}

find_block() {
  local name model part label

  while read -r name model; do
    [[ -n "$name" ]] || continue
    while read -r part; do
      [[ "$part" == "$name" ]] && continue
      if [[ -n "$(lsblk -no FSTYPE "/dev/$part" 2>/dev/null)" ]]; then
        echo "/dev/$part"
        return 0
      fi
    done < <(lsblk -lno NAME "/dev/$name" 2>/dev/null)

    if [[ -n "$(lsblk -no FSTYPE "/dev/$name" 2>/dev/null)" ]]; then
      echo "/dev/$name"
      return 0
    fi
  done < <(lsblk -dn -o NAME,MODEL 2>/dev/null | awk 'tolower($0) ~ /garmin/')

  while read -r name label; do
    [[ -n "$name" ]] || continue
    if printf '%s' "$label" | grep -qi garmin; then
      echo "/dev/$name"
      return 0
    fi
  done < <(lsblk -ln -o NAME,LABEL 2>/dev/null)

  return 1
}

mount_block() {
  local dev mp
  dev="$(find_block)" || return 1
  mp="$(lsblk -no MOUNTPOINT "$dev" 2>/dev/null | head -1)"

  if [[ -z "$mp" ]]; then
    command -v udisksctl >/dev/null 2>&1 \
      || die "Found $dev but udisksctl is missing. Mount it manually and set WATCH_ROOT."
    info "Mounting $dev"
    udisksctl mount -b "$dev" >/dev/null
    sleep 1
    mp="$(lsblk -no MOUNTPOINT "$dev" 2>/dev/null | head -1)"
  fi

  [[ -n "$mp" ]] || die "Could not mount $dev"
  WATCH_KIND="block"
  WATCH_ROOT="$mp"
  return 0
}

resolve_root() {
  if [[ -n "${WATCH_ROOT_OVERRIDE:-}" ]]; then
    WATCH_KIND="block"
    WATCH_ROOT="$WATCH_ROOT_OVERRIDE"
    return
  fi
  if mount_block; then
    return
  fi
  ensure_mtp_mounted
}

resolve_garmin_dir() {
  local d base
  for d in "$WATCH_ROOT/Garmin" "$WATCH_ROOT/GARMIN" "$WATCH_ROOT/garmin"; do
    if [[ -d "$d" ]]; then
      GARMIN_DIR="$d"
      return
    fi
  done
  for d in "$WATCH_ROOT"/*; do
    [[ -d "$d" ]] || continue
    base="$(basename "$d")"
    case "$base" in
      [Gg][Aa][Rr][Mm][Ii][Nn]) GARMIN_DIR="$d"; return ;;
    esac
  done
  die "No Garmin folder found under $WATCH_ROOT"
}

prepare() {
  resolve_root
  resolve_garmin_dir
}

xml_field() {
  local field="$1" xml="$GARMIN_DIR/GarminDevice.xml"
  [[ -f "$xml" ]] || return 0
  grep -oE "<$field>[^<]*" "$xml" | head -1 | sed 's/<[^>]*>//'
}

format_version() {
  local v="$1"
  if [[ "$v" =~ ^[0-9]+$ ]]; then
    printf '%d.%02d' $((v / 100)) $((v % 100))
  else
    printf '%s' "$v"
  fi
}

free_bytes() {
  df -B1 --output=avail "$WATCH_ROOT" | tail -1 | tr -d ' '
}

find_package_dir() {
  local hits count
  [[ -d "$PACKAGE_DIR" ]] || return 1
  hits="$(find "$PACKAGE_DIR" -maxdepth 2 -iname 'gupdate.gsp' -print 2>/dev/null \
    | while read -r f; do dirname "$f"; done | sort -u)"
  count="$(printf '%s\n' "$hits" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [[ "$count" == "1" ]]; then
    printf '%s\n' "$hits"
    return 0
  fi
  if [[ "$count" == "0" ]]; then
    return 1
  fi
  die "Multiple packages found under $PACKAGE_DIR; use --package DIR"
}

cmd_status() {
  local part version desc avail
  prepare
  part="$(xml_field PartNumber)"
  version="$(xml_field SoftwareVersion)"
  desc="$(xml_field Description)"
  avail="$(free_bytes)"

  info "Connection: $WATCH_KIND"
  info "Garmin folder: <watch>/${GARMIN_DIR##*/}"
  echo "Model:            ${desc:-unknown}"
  echo "Part number:      ${part:-unknown}"
  if [[ -n "$version" ]]; then
    echo "Software version: $version ($(format_version "$version"))"
  else
    echo "Software version: unknown"
  fi
  echo "Free bytes:       $avail"
  df -h "$WATCH_ROOT" 2>/dev/null || true

  echo "--- cleanup targets ---"
  local p rel found=0
  for p in "$GARMIN_DIR/ExtData" "$GARMIN_DIR/NewFiles" "$GARMIN_DIR"/GUPDATE* "$GARMIN_DIR"/gupdate*; do
    if [[ -e "$p" ]]; then
      rel="${p#"$WATCH_ROOT"/}"
      if [[ -d "$p" ]]; then
        echo "<watch>/$rel/"
      else
        echo "<watch>/$rel ($(stat -c %s "$p" 2>/dev/null || echo '?') bytes)"
      fi
      found=1
    fi
  done
  [[ "$found" == "1" ]] || echo "none"

  echo "--- package ---"
  local pkg
  if pkg="$(find_package_dir 2>/dev/null)"; then
    echo "Package dir: ${pkg#"$REPO_DIR"/}"
    stat -c 'gupdate.gsp: %s bytes' "$pkg/gupdate.gsp" 2>/dev/null || true
  else
    echo "No extracted package found under ${PACKAGE_DIR#"$REPO_DIR"/}"
  fi
}

cmd_clean() {
  local extra="${1:-}"
  prepare
  info "Cleaning known update junk"

  if [[ -d "$GARMIN_DIR/ExtData" ]]; then
    rm -rf "$GARMIN_DIR/ExtData"
    echo "removed ExtData"
  fi

  if [[ -d "$GARMIN_DIR/NewFiles" ]]; then
    find "$GARMIN_DIR/NewFiles" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
    echo "emptied NewFiles"
  fi

  local f
  for f in "$GARMIN_DIR"/GUPDATE* "$GARMIN_DIR"/gupdate*; do
    rm -f "$f"
    echo "removed $(basename "$f")"
  done

  if [[ "$extra" == "--extra" ]]; then
    local d
    for d in RemoteSW DEBUG SUMMARY Sports FbtBackup FbtPtdBackup TempFIT; do
      if [[ -d "$GARMIN_DIR/$d" ]]; then
        find "$GARMIN_DIR/$d" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
        echo "emptied $d"
      fi
    done
  fi

  echo "free bytes: $(free_bytes)"
  df -h "$WATCH_ROOT" 2>/dev/null || true
}

cmd_install() {
  local pkg="" arg="${1:-}"
  if [[ "$arg" == "--package" ]]; then
    pkg="${2:-}"
    [[ -n "$pkg" ]] || die "--package needs a directory"
  elif [[ -n "$arg" ]]; then
    pkg="$arg"
  fi
  if [[ -z "$pkg" ]]; then
    pkg="$(find_package_dir)" || die "No extracted package under $PACKAGE_DIR. Run fetch-firmware.sh first."
  fi
  [[ -d "$pkg" ]] || die "Package directory not found: $pkg"

  local src_gsp src_force
  src_gsp="$(find "$pkg" -maxdepth 1 -iname 'gupdate.gsp' -print -quit 2>/dev/null)"
  src_force="$(find "$pkg" -maxdepth 1 -iname 'force.tmp' -print -quit 2>/dev/null)"
  [[ -n "$src_gsp" ]] || die "gupdate.gsp not found in $pkg"
  [[ -n "$src_force" ]] || die "force.tmp not found in $pkg"

  prepare

  local need avail
  need="$(stat -c %s "$src_gsp")"
  avail="$(free_bytes)"
  info "Free: $avail bytes; package: $need bytes"
  (( avail > need + 1048576 )) \
    || die "Not enough free space (need package + 1 MiB margin). Run clean --extra first."

  local target_gsp="$GARMIN_DIR/GUPDATE.GSP"
  local target_force="$GARMIN_DIR/force.tmp"

  # Remove stale copies so a partial transfer cannot be mistaken for a valid one.
  rm -f "$GARMIN_DIR"/GUPDATE* "$GARMIN_DIR"/gupdate* 2>/dev/null || true

  if [[ "$WATCH_KIND" == "mtp" ]]; then
    local rel base
    rel="${GARMIN_DIR#"$WATCH_ROOT"/}"
    base="${MTP_URI%/}/$rel"
    info "Copying force.tmp over MTP"
    gio copy "$src_force" "$base/force.tmp"
    info "Copying GUPDATE.GSP over MTP (~20 MB)"
    gio copy "$src_gsp" "$base/GUPDATE.GSP"
  else
    info "Copying force.tmp"
    cp -f "$src_force" "$target_force"
    info "Copying GUPDATE.GSP"
    cp -f "$src_gsp" "$target_gsp"
  fi

  sync || true

  local got
  got="$(stat -c %s "$target_gsp")"
  [[ "$got" == "$need" ]] || die "Size mismatch after copy: $got != $need"

  local sha_file="$pkg/gupdate.gsp.sha256"
  if [[ -f "$sha_file" ]]; then
    local expected actual
    expected="$(awk '{print $1}' "$sha_file")"
    actual="$(sha256sum "$target_gsp" | awk '{print $1}')"
    if [[ "$actual" != "$expected" ]]; then
      die "SHA-256 mismatch after copy. Delete GUPDATE.GSP and retry."
    fi
    info "SHA-256 verified: $actual"
  else
    warn "No gupdate.gsp.sha256 in $pkg; size checked only."
  fi

  info "Files in place:"
  printf '  <watch>/%s (%s bytes)\n' \
    "${target_force#"$WATCH_ROOT"/}" "$(stat -c %s "$target_force")"
  printf '  <watch>/%s (%s bytes)\n' \
    "${target_gsp#"$WATCH_ROOT"/}" "$(stat -c %s "$target_gsp")"
  echo
  info "Next: unmount, unplug, power on, accept the update, wait up to 30 min."
}

cmd_unmount() {
  if [[ -n "$WATCH_ROOT_OVERRIDE" ]]; then
    info "Watch root was provided manually; unmount it with your system tools."
    return
  fi
  if [[ -z "$WATCH_KIND" ]]; then
    resolve_root
  fi
  if [[ "$WATCH_KIND" == "mtp" ]]; then
    local uri="${MTP_URI:-}"
    [[ -n "$uri" ]] || uri="$(discover_mtp_uri)"
    gio mount -u "$uri" 2>/dev/null || true
    info "Unmounted MTP"
    return
  fi
  local dev
  dev="$(find_block)" || die "No Garmin block device found"
  udisksctl unmount -b "$dev" >/dev/null 2>&1 || true
  info "Unmounted $dev"
}

cmd_verify() {
  local version
  prepare
  version="$(xml_field SoftwareVersion)"
  [[ -n "$version" ]] || die "Could not read SoftwareVersion from GarminDevice.xml"
  echo "SoftwareVersion: $version ($(format_version "$version"))"
  echo "Free bytes:      $(free_bytes)"
}

main() {
  local cmd="${1:-status}"
  shift || true

  case "$cmd" in
    status)  cmd_status ;;
    mount)   prepare; printf '%s\n' "$WATCH_ROOT" ;;
    clean)   cmd_clean "${1:-}" ;;
    install) cmd_install "${1:-}" "${2:-}" ;;
    unmount) cmd_unmount ;;
    verify)  cmd_verify ;;
    -h|--help|help) usage ;;
    *) usage; exit 2 ;;
  esac
}

main "$@"
