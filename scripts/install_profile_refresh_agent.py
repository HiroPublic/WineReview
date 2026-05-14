#!/usr/bin/env python3

from __future__ import annotations

import argparse
import os
import plistlib
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_LABEL = "com.example.wine-review.profile-refresh"
DEFAULT_LOG_DIR = Path.home() / "Library" / "Logs"


def run(command: list[str]) -> None:
    print("+ " + " ".join(command))
    subprocess.run(command, check=True)


def main() -> int:
    parser = argparse.ArgumentParser(description="Install the Wine Review profile refresh LaunchAgent.")
    parser.add_argument("--label", default=DEFAULT_LABEL)
    parser.add_argument("--device-name", default=os.environ.get("WINE_REVIEW_DEVICE_NAME"))
    parser.add_argument("--device-id", default=os.environ.get("WINE_REVIEW_DEVICE_ID"))
    parser.add_argument("--threshold-days", default="2")
    parser.add_argument("--interval-seconds", default="3600")
    parser.add_argument("--calendar-hour", default="8")
    parser.add_argument("--calendar-minute", default="30")
    parser.add_argument("--dry-run", action="store_true", help="Print the generated plist without writing it.")
    parser.add_argument("--load", action="store_true", help="Load the LaunchAgent after writing the plist.")
    args = parser.parse_args()

    if not args.device_name and not args.device_id:
        raise SystemExit("Set --device-name, --device-id, WINE_REVIEW_DEVICE_NAME, or WINE_REVIEW_DEVICE_ID.")

    arguments = [
        "/usr/bin/python3",
        str(ROOT / "scripts" / "refresh_ios_profile.py"),
        "--threshold-days",
        str(args.threshold_days),
    ]
    if args.device_id:
        arguments.extend(["--device-id", args.device_id])
    if args.device_name:
        arguments.extend(["--device-name", args.device_name])

    data = {
        "Label": args.label,
        "ProgramArguments": arguments,
        "EnvironmentVariables": {
            "HOME": str(Path.home()),
            "LOGNAME": os.environ.get("LOGNAME", Path.home().name),
            "USER": os.environ.get("USER", Path.home().name),
        },
        "RunAtLoad": True,
        "StartInterval": int(args.interval_seconds),
        "StartCalendarInterval": {
            "Hour": int(args.calendar_hour),
            "Minute": int(args.calendar_minute),
        },
        "StandardOutPath": str(DEFAULT_LOG_DIR / "wine-review-profile-refresh.log"),
        "StandardErrorPath": str(DEFAULT_LOG_DIR / "wine-review-profile-refresh.err"),
        "WorkingDirectory": str(ROOT),
    }

    if args.dry_run:
        print(plistlib.dumps(data, sort_keys=False).decode("utf-8"), end="")
        return 0

    launch_agents = Path.home() / "Library" / "LaunchAgents"
    launch_agents.mkdir(parents=True, exist_ok=True)
    plist_path = launch_agents / f"{args.label}.plist"

    with plist_path.open("wb") as file:
        plistlib.dump(data, file, sort_keys=False)

    print(f"Wrote {plist_path}")
    run(["plutil", "-lint", str(plist_path)])

    if args.load:
        uid = os.getuid()
        subprocess.run(["launchctl", "bootout", f"gui/{uid}/{args.label}"], check=False)
        run(["launchctl", "bootstrap", f"gui/{uid}", str(plist_path)])

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
