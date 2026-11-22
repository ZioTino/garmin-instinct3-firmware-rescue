#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Discover the latest live system-software package for a Garmin model.

Garmin Express asks Garmin's OMT service for updates by posting the device's
GarminDevice.xml. This script does the same thing with a sanitized XML:

  * the unit id is replaced with a neutral value (1)
  * <Extensions> and <DataType> elements are removed

No serial number, account, or real unit id is sent.

The service returns JSON with SoftwareUpdateOptions. This script selects the
system bundle (GUPDATE.GSP / GUPDATE.GCD) and prints a small JSON description
on stdout.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.request
from typing import NoReturn

ENDPOINT = (
    "https://omt.garmin.com/Rce/ProtobufApi/"
    "SoftwareUpdateService/GetAllUnitSoftwareUpdates"
)
SYSTEM_FILES = {"GUPDATE.GSP", "GUPDATE.GCD"}


def die(message: str) -> NoReturn:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def sanitize_xml(xml: str) -> str:
    """Strip personal/irrelevant parts and use a neutral unit id."""
    xml = re.sub(r"<!--.*?-->", "", xml, flags=re.S)
    xml = re.sub(r"<Extensions\b.*?</Extensions>", "", xml, flags=re.S)
    xml = re.sub(r"<DataType\b.*?</DataType>", "", xml, flags=re.S)

    if re.search(r"<Id\b[^>]*>.*?</Id>", xml, flags=re.S):
        xml = re.sub(
            r"<Id\b[^>]*>.*?</Id>", "<Id>1</Id>", xml, count=1, flags=re.S
        )
    elif "</Model>" in xml:
        xml = xml.replace("</Model>", "</Model><Id>1</Id>", 1)

    return xml.strip()


def build_xml(package_part: str, version: int = 0) -> str:
    """Build a minimal GarminDevice.xml for a package id."""
    package_part = package_part.strip().upper()
    if re.fullmatch(r"006-B\d{4}-\d{2}", package_part):
        package_part = package_part.replace("006-B", "006-V", 1)
    if not re.fullmatch(r"006-V\d{4}-\d{2}", package_part):
        die(f"Unsupported package id: {package_part!r}")

    device_part = package_part.replace("006-V", "006-B", 1)
    return (
        '<Device xmlns="http://www.garmin.com/xmlschemas/GarminDevice/v2">'
        "<Model>"
        f"<PartNumber>{device_part}</PartNumber>"
        f"<SoftwareVersion>{int(version)}</SoftwareVersion>"
        "<Description>auto</Description>"
        "</Model>"
        "<Id>1</Id>"
        "<MassStorageMode>"
        "<UpdateFile>"
        f"<PartNumber>{package_part}</PartNumber>"
        "<Version><Major>0</Major><Minor>0</Minor></Version>"
        "<Path>Garmin</Path>"
        "<FileName>GUPDATE.GSP</FileName>"
        "</UpdateFile>"
        "</MassStorageMode>"
        "</Device>"
    )


def version_key(value) -> tuple[int, int]:
    """Normalize both Garmin forms: 521 -> 5.21, 1519 -> 15.19, 15.19 -> 15.19."""
    text = str(value).strip()
    if "." in text:
        nums = [int(n) for n in re.findall(r"\d+", text)]
        return (nums[0], nums[1] if len(nums) > 1 else 0)
    if text.isdigit():
        number = int(text)
        if number >= 100:
            return number // 100, number % 100
        return number, 0
    nums = [int(n) for n in re.findall(r"\d+", text)]
    if not nums:
        return 0, 0
    return (nums[0], nums[1] if len(nums) > 1 else 0)


def query(xml: str) -> dict:
    body = json.dumps(
        {
            "ClientInfo": {},
            "GarminDeviceXml": sanitize_xml(xml),
            "IsUserInteractive": False,
        }
    ).encode("utf-8")

    request = urllib.request.Request(
        ENDPOINT,
        data=body,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Accept": "application/json",
            "X-garmin-client-id": "EXPRESS",
            "User-Agent": "garmin-instinct3-firmware-rescue/1.0",
        },
    )

    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            raw = response.read()
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")[:1000]
        die(f"Garmin update service returned HTTP {exc.code}: {detail}")
    except urllib.error.URLError as exc:
        die(f"Could not reach Garmin update service: {exc.reason}")

    try:
        return json.loads(raw)
    except json.JSONDecodeError as exc:
        die(f"Garmin update service returned invalid JSON: {exc}")


def pick_system_update(data: dict) -> dict:
    options = data.get("SoftwareUpdateOptions") or []
    candidates: list[tuple[tuple[int, int], int, dict]] = []

    for option in options:
        file_path = str(option.get("FilePathOnUnit") or "").replace("\\", "/")
        file_name = file_path.rsplit("/", 1)[-1].upper()
        data_type = str(option.get("DataType") or "").casefold()
        part = str(option.get("PartNumber") or "")

        if file_name in SYSTEM_FILES:
            candidates.append(
                (
                    version_key(option.get("SoftwareVersion")),
                    int(option.get("InstallationOrder") or 0),
                    option,
                )
            )
        elif data_type == "firmware" and part.startswith("006-V"):
            # Fallback for a response that omits FilePathOnUnit.
            candidates.append(
                (
                    version_key(option.get("SoftwareVersion")),
                    int(option.get("InstallationOrder") or 0),
                    option,
                )
            )

    if not candidates:
        summary = [
            {
                "part": o.get("PartNumber"),
                "version": o.get("SoftwareVersion"),
                "type": o.get("DataType"),
                "path": o.get("FilePathOnUnit"),
            }
            for o in options
        ]
        die(f"No GUPDATE.GSP/GCD system update in the response: {summary}")

    # Highest version wins; installation order breaks ties.
    return max(candidates, key=lambda item: (item[0], item[1]))[2]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--xml", metavar="FILE", help="GarminDevice.xml to query")
    source.add_argument("--model", metavar="ID", help="package id, e.g. 006-V4585-00")
    parser.add_argument(
        "--version", type=int, default=0, help="installed version for --model (integer)"
    )
    parser.add_argument(
        "--require-live",
        action="store_true",
        help="fail unless Garmin returns AccessLevel 'live'",
    )
    args = parser.parse_args()

    if args.xml:
        try:
            with open(args.xml, encoding="utf-8") as handle:
                xml = handle.read()
        except OSError as exc:
            die(f"Could not read {args.xml}: {exc}")
    else:
        xml = build_xml(args.model, args.version)

    installed_match = re.search(r"<SoftwareVersion>(\d+)</SoftwareVersion>", xml)
    installed_version = installed_match.group(1) if installed_match else None

    data = query(xml)
    access = str(data.get("AccessLevel") or "")
    if access.casefold() != "live":
        message = f"Garmin returned access level {access!r}, expected 'live'"
        if args.require_live:
            die(message)
        print(f"WARNING: {message}", file=sys.stderr)

    option = pick_system_update(data)
    url = str((option.get("Url") or {}).get("Url") or "")
    if not url:
        die("Selected update has no download URL")
    if url.startswith("http://"):
        url = "https://" + url[len("http://") :]
    # Garmin sometimes returns ZIP names with literal spaces.
    url = url.replace(" ", "%20")

    selected_version = str(option.get("SoftwareVersion"))
    if installed_version and version_key(selected_version) < version_key(installed_version):
        print(
            f"WARNING: live version {selected_version} is older than the installed "
            f"version {installed_version}; this would be a downgrade",
            file=sys.stderr,
        )

    result = {
        "accessLevel": access,
        "installedVersion": installed_version,
        "packagePartNumber": option.get("PartNumber"),
        "version": selected_version,
        "url": url,
        "md5": (option.get("Url") or {}).get("Md5"),
        "size": (option.get("Url") or {}).get("Size"),
        "filePathOnUnit": option.get("FilePathOnUnit"),
        "displayName": option.get("DisplayName"),
        "isReinstall": bool(option.get("IsReinstall")),
        "changes": option.get("Changes") or [],
    }
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
