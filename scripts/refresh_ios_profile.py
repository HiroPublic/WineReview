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
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "WineReview.xcodeproj"
DERIVED_DATA = ROOT / "DerivedData" / "DeviceRun"
APP = DERIVED_DATA / "Build" / "Products" / "Debug-iphoneos" / "WineReview.app"
PROFILE = APP / "embedded.mobileprovision"
STATE_FILE = ROOT / "DerivedData" / "profile-refresh-state.json"
SCHEME = "WineReview"
DEFAULT_THRESHOLD_DAYS = 2.0
DEFAULT_RETRY_COOLDOWN_HOURS = 1.0
DEFAULT_MIN_EXTENSION_HOURS = 1.0
DEFAULT_XCODE_LAUNCH_WAIT_SECONDS = 20.0
PROVISIONING_PROFILE_DIR = Path.home() / "Library" / "Developer" / "Xcode" / "UserData" / "Provisioning Profiles"
NO_ACCOUNTS_MARKERS = (
    "No Accounts",
    "Add a new account in Accounts settings",
)
MISSING_PROFILE_MARKERS = (
    "No profiles for",
    "Provisioning profile",
    "provisioning profiles matching",
)


def run(command: list[str], *, capture: bool = False, check: bool = True) -> subprocess.CompletedProcess[str]:
    print("+ " + " ".join(shlex.quote(part) for part in command))
    return subprocess.run(
        command,
        cwd=ROOT,
        check=check,
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


def format_local(value: datetime) -> str:
    return value.astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")


def remaining_hours_until(value: datetime) -> float:
    return (value - datetime.now(timezone.utc)).total_seconds() / 3600


def iso_datetime(value: datetime | None) -> str | None:
    if value is None:
        return None
    return utc_datetime(value).isoformat()


def parse_iso_datetime(value: object) -> datetime | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        return utc_datetime(datetime.fromisoformat(value))
    except ValueError:
        return None


def load_state() -> dict:
    try:
        return json.loads(STATE_FILE.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}
    except json.JSONDecodeError:
        return {}


def save_state(state: dict) -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n", encoding="utf-8")


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


def current_profile_uuid(profile_path: Path) -> str | None:
    try:
        profile = extract_profile_plist(profile_path)
    except FileNotFoundError:
        return None

    uuid = profile.get("UUID")
    return uuid if isinstance(uuid, str) and uuid else None


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


def retire_local_profile(profile_uuid: str | None) -> Path | None:
    if not profile_uuid:
        return None

    profile_path = PROVISIONING_PROFILE_DIR / f"{profile_uuid}.mobileprovision"
    if not profile_path.exists():
        return None

    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
    backup_path = profile_path.with_suffix(f".mobileprovision.retired-{timestamp}")
    print(f"Retiring local provisioning profile {profile_path} -> {backup_path}")
    profile_path.rename(backup_path)
    return backup_path


def restore_local_profile(profile_uuid: str | None, backup_path: Path | None) -> None:
    if not profile_uuid or not backup_path or not backup_path.exists():
        return

    profile_path = PROVISIONING_PROFILE_DIR / f"{profile_uuid}.mobileprovision"
    if profile_path.exists():
        print(f"Skipping restore because current profile already exists at {profile_path}")
        return

    print(f"Restoring local provisioning profile {backup_path} -> {profile_path}")
    backup_path.rename(profile_path)


def build_command() -> list[str]:
    return [
        "xcodebuild",
        "-allowProvisioningUpdates",
        "-project",
        str(PROJECT),
        "-scheme",
        SCHEME,
        "-destination",
        "generic/platform=iOS",
        "-derivedDataPath",
        str(DERIVED_DATA),
        "build",
    ]


def emit_result_output(result: subprocess.CompletedProcess[str]) -> None:
    if result.stdout:
        print(result.stdout, end="" if result.stdout.endswith("\n") else "\n")
    if result.stderr:
        print(result.stderr, end="" if result.stderr.endswith("\n") else "\n", file=sys.stderr)


def result_text(result: subprocess.CompletedProcess[str]) -> str:
    return "\n".join(part for part in (result.stdout, result.stderr) if part)


def has_any_marker(text: str, markers: tuple[str, ...]) -> bool:
    return any(marker in text for marker in markers)


def launch_xcode(wait_seconds: float) -> None:
    print("Launching Xcode to restore the signing account session.")
    run(["open", "-ga", "Xcode"], capture=True)
    time.sleep(wait_seconds)


def build_with_retry(*, xcode_launch_wait_seconds: float) -> subprocess.CompletedProcess[str]:
    result = run(build_command(), capture=True, check=False)
    emit_result_output(result)
    if result.returncode == 0:
        return result

    text = result_text(result)
    if not has_any_marker(text, NO_ACCOUNTS_MARKERS):
        return result

    print("xcodebuild could not access the configured Xcode account. Retrying after launching Xcode.")
    launch_xcode(xcode_launch_wait_seconds)
    retry_result = run(build_command(), capture=True, check=False)
    emit_result_output(retry_result)
    return retry_result


def install(device_id: str) -> None:
    run(["xcrun", "devicectl", "device", "install", "app", "--device", device_id, str(APP)])


def effective_cooldown_hours(expiration: datetime | None, cooldown_hours: float) -> float:
    if expiration is None:
        return cooldown_hours

    remaining_hours = remaining_hours_until(expiration)
    if remaining_hours <= 0:
        return 0.25

    return max(0.25, min(cooldown_hours, remaining_hours / 3))


def should_wait_for_cooldown(expiration: datetime | None, cooldown_hours: float) -> tuple[bool, str | None]:
    state = load_state()
    last_attempt_at = parse_iso_datetime(state.get("last_attempt_at"))
    last_attempt_expiration = state.get("last_attempt_expiration")
    current_expiration = iso_datetime(expiration)

    if not last_attempt_at or last_attempt_expiration != current_expiration:
        return False, None

    cooldown = effective_cooldown_hours(expiration, cooldown_hours)
    retry_at = last_attempt_at + timedelta(hours=cooldown)
    now = datetime.now(timezone.utc)
    if now >= retry_at:
        return False, None

    return True, f"Previous attempt did not extend this profile. Next retry after {format_local(retry_at)}."


def record_attempt(expiration: datetime | None, outcome: str) -> None:
    state = load_state()
    state.update(
        {
            "last_attempt_at": datetime.now(timezone.utc).isoformat(),
            "last_attempt_expiration": iso_datetime(expiration),
            "last_outcome": outcome,
        }
    )
    save_state(state)


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
    parser.add_argument("--retry-cooldown-hours", type=float, default=DEFAULT_RETRY_COOLDOWN_HOURS)
    parser.add_argument("--min-extension-hours", type=float, default=DEFAULT_MIN_EXTENSION_HOURS)
    parser.add_argument("--xcode-launch-wait-seconds", type=float, default=DEFAULT_XCODE_LAUNCH_WAIT_SECONDS)
    args = parser.parse_args()
    notify_enabled = not args.no_notify

    remaining, expiration = remaining_days(PROFILE)
    needs_refresh = args.force or remaining is None or remaining <= args.threshold_days

    if expiration is not None and remaining is not None:
        print(f"Current profile expires at {format_local(expiration)} ({remaining:.2f} days remaining).")

    if not needs_refresh:
        print(f"No refresh needed. Threshold is {args.threshold_days:.2f} days.")
        return 0

    waiting, cooldown_message = should_wait_for_cooldown(expiration, args.retry_cooldown_hours)
    if waiting and not args.force:
        print(cooldown_message)
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
    original_profile_uuid = current_profile_uuid(PROFILE)
    retired_backup_path: Path | None = None
    try:
        build_result = build_with_retry(xcode_launch_wait_seconds=args.xcode_launch_wait_seconds)
        if build_result.returncode != 0:
            failure_text = result_text(build_result)
            if original_profile_uuid and has_any_marker(failure_text, MISSING_PROFILE_MARKERS + NO_ACCOUNTS_MARKERS):
                retired_backup_path = retire_local_profile(original_profile_uuid)
                if retired_backup_path is not None:
                    print("Retrying build after retiring the cached provisioning profile.")
                    build_result = build_with_retry(xcode_launch_wait_seconds=args.xcode_launch_wait_seconds)
            if build_result.returncode != 0:
                raise subprocess.CalledProcessError(
                    build_result.returncode,
                    build_command(),
                    output=build_result.stdout,
                    stderr=build_result.stderr,
                )
        install(device_id)
    except subprocess.CalledProcessError as error:
        restore_local_profile(original_profile_uuid, retired_backup_path)
        command = shlex.join(error.cmd) if isinstance(error.cmd, list) else str(error.cmd)
        message = f"Command failed: {command}"
        print(message, file=sys.stderr)
        notify("Wine Review profile refresh failed", message, enabled=notify_enabled)
        record_attempt(expiration, "command_failed")
        return error.returncode

    refreshed_remaining, refreshed_expiration = remaining_days(PROFILE)
    if refreshed_expiration is not None and refreshed_remaining is not None:
        print(f"Post-refresh profile expires at {format_local(refreshed_expiration)} ({refreshed_remaining:.2f} days remaining).")

        min_extension = timedelta(hours=args.min_extension_hours)
        if (
            expiration is not None
            and refreshed_expiration <= expiration + min_extension
            and retired_backup_path is None
            and original_profile_uuid == current_profile_uuid(PROFILE)
        ):
            print("Build completed with the previous profile still embedded. Retrying once after retiring the cached profile.")
            retired_backup_path = retire_local_profile(original_profile_uuid)
            if retired_backup_path is not None:
                try:
                    build_result = build_with_retry(xcode_launch_wait_seconds=args.xcode_launch_wait_seconds)
                    if build_result.returncode != 0:
                        raise subprocess.CalledProcessError(
                            build_result.returncode,
                            build_command(),
                            output=build_result.stdout,
                            stderr=build_result.stderr,
                        )
                    install(device_id)
                except subprocess.CalledProcessError as error:
                    restore_local_profile(original_profile_uuid, retired_backup_path)
                    command = shlex.join(error.cmd) if isinstance(error.cmd, list) else str(error.cmd)
                    message = f"Command failed: {command}"
                    print(message, file=sys.stderr)
                    notify("Wine Review profile refresh failed", message, enabled=notify_enabled)
                    record_attempt(expiration, "command_failed")
                    return error.returncode

                refreshed_remaining, refreshed_expiration = remaining_days(PROFILE)
                if refreshed_expiration is not None and refreshed_remaining is not None:
                    print(
                        f"Post-retire profile expires at {format_local(refreshed_expiration)} ({refreshed_remaining:.2f} days remaining)."
                    )

        if expiration is not None and refreshed_expiration <= expiration + min_extension:
            effective_cooldown = effective_cooldown_hours(expiration, args.retry_cooldown_hours)
            message = (
                "Build and install completed, but the provisioning profile expiration did not extend. "
                f"Current expiration is still {format_local(refreshed_expiration)}. "
                f"Next retry is delayed for {effective_cooldown:g} hours."
            )
            print(message)
            notify("Wine Review profile not extended", message, enabled=notify_enabled)
            record_attempt(expiration, "not_extended")
            return 0

        record_attempt(refreshed_expiration, "extended")
        notify(
            "Wine Review profile refreshed",
            f"New profile expires at {format_local(refreshed_expiration)}.",
            enabled=notify_enabled,
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
