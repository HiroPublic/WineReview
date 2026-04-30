#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import plistlib
import re
import shlex
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "WineReview.xcodeproj"
DERIVED_DATA = ROOT / "DerivedData" / "DeviceRun"
APP = DERIVED_DATA / "Build" / "Products" / "Debug-iphoneos" / "WineReview.app"
PROFILE = APP / "embedded.mobileprovision"
SCHEME = "WineReview"
DEFAULT_THRESHOLD_DAYS = 2.0


def run(command: list[str], *, capture: bool = False) -> subprocess.CompletedProcess[str]:
    print("+ " + " ".join(shlex.quote(part) for part in command))
    return subprocess.run(
        command,
        cwd=ROOT,
        check=True,
        text=True,
        capture_output=capture,
    )


def notify(title: str, message: str, *, enabled: bool) -> None:
    if not enabled:
        return

    script = f"display notification {json.dumps(message)} with title {json.dumps(title)}"
    try:
        run(["osascript", "-e", script], capture=True)
    except Exception as error:
        print(f"Notification failed: {error}", file=sys.stderr)


def extract_profile_plist(profile_path: Path) -> dict:
    if not profile_path.exists():
        raise FileNotFoundError(profile_path)

    output = run(["strings", str(profile_path)], capture=True).stdout
    match = re.search(r"(<\?xml\b.*?</plist>)", output, re.DOTALL)
    if not match:
        raise ValueError(f"Could not find plist XML in {profile_path}")

    return plistlib.loads(match.group(1).encode("utf-8"))


def utc_datetime(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def remaining_days(profile_path: Path) -> tuple[float | None, datetime | None]:
    try:
        profile = extract_profile_plist(profile_path)
    except FileNotFoundError:
        print(f"Profile not found: {profile_path}")
        return None, None

    expiration = profile.get("ExpirationDate")
    if not isinstance(expiration, datetime):
        raise ValueError(f"ExpirationDate not found in {profile_path}")

    expiration = utc_datetime(expiration)
    remaining = (expiration - datetime.now(timezone.utc)).total_seconds() / 86400
    return remaining, expiration


def find_device_id(device_id: str | None, device_name: str | None) -> str:
    if device_id:
        return device_id

    if not device_name:
        raise ValueError("Set --device-id, --device-name, or WINE_REVIEW_DEVICE_NAME.")

    result = run(["xcrun", "devicectl", "list", "devices"], capture=True)
    for line in result.stdout.splitlines():
        if device_name not in line or "available" not in line:
            continue

        match = re.search(
            r"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b",
            line,
        )
        if match:
            return match.group(0)

    raise ValueError(f"No available paired device matched --device-name {device_name!r}.")


def build(device_id: str) -> None:
    run(
        [
            "xcodebuild",
            "-allowProvisioningUpdates",
            "-project",
            str(PROJECT),
            "-scheme",
            SCHEME,
            "-destination",
            f"platform=iOS,id={device_id}",
            "-derivedDataPath",
            str(DERIVED_DATA),
            "build",
        ]
    )


def install(device_id: str) -> None:
    run(["xcrun", "devicectl", "device", "install", "app", "--device", device_id, str(APP)])


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Refresh the iOS development provisioning profile before Wine Review expires."
    )
    parser.add_argument("--threshold-days", type=float, default=DEFAULT_THRESHOLD_DAYS)
    parser.add_argument("--device-id", default=os.environ.get("WINE_REVIEW_DEVICE_ID"))
    parser.add_argument("--device-name", default=os.environ.get("WINE_REVIEW_DEVICE_NAME"))
    parser.add_argument("--force", action="store_true", help="Rebuild and reinstall even if the profile is fresh.")
    parser.add_argument("--dry-run", action="store_true", help="Print what would happen without rebuilding.")
    parser.add_argument("--no-notify", action="store_true", help="Do not show macOS notifications.")
    args = parser.parse_args()
    notify_enabled = not args.no_notify

    remaining, expiration = remaining_days(PROFILE)
    needs_refresh = args.force or remaining is None or remaining <= args.threshold_days

    if expiration is not None and remaining is not None:
        local_expiration = expiration.astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")
        print(f"Current profile expires at {local_expiration} ({remaining:.2f} days remaining).")

    if not needs_refresh:
        print(f"No refresh needed. Threshold is {args.threshold_days:.2f} days.")
        return 0

    print("Profile refresh is needed.")
    notify(
        "Wine Review profile refresh",
        "Provisioning profile is near expiration. Rebuilding and reinstalling Wine Review.",
        enabled=notify_enabled and not args.dry_run,
    )
    if args.dry_run:
        print("Dry run: skipping build and install.")
        return 0

    try:
        device_id = find_device_id(args.device_id, args.device_name)
    except Exception as error:
        print(f"Cannot refresh profile: {error}", file=sys.stderr)
        notify("Wine Review profile refresh failed", str(error), enabled=notify_enabled)
        return 2

    print(f"Refreshing Wine Review on device {device_id}.")
    try:
        build(device_id)
        install(device_id)
    except subprocess.CalledProcessError as error:
        command = shlex.join(error.cmd) if isinstance(error.cmd, list) else str(error.cmd)
        message = f"Command failed: {command}"
        print(message, file=sys.stderr)
        notify("Wine Review profile refresh failed", message, enabled=notify_enabled)
        return error.returncode

    refreshed_remaining, refreshed_expiration = remaining_days(PROFILE)
    if refreshed_expiration is not None and refreshed_remaining is not None:
        local_expiration = refreshed_expiration.astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")
        print(f"Refreshed profile expires at {local_expiration} ({refreshed_remaining:.2f} days remaining).")
        notify(
            "Wine Review profile refreshed",
            f"New profile expires at {local_expiration}.",
            enabled=notify_enabled,
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
