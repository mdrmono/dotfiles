#!/usr/bin/python3
"""Capture an open X11 dropdown when Super is tapped twice."""

from __future__ import annotations

import fcntl
import os
from pathlib import Path
import struct
import subprocess
import time

from Xlib import XK, display
from Xlib.ext import xinput


SCREENSHOT = Path(__file__).with_name("screenshot.sh")
DOUBLE_TAP_SECONDS = 0.45


def main() -> None:
    runtime = Path(os.environ.get("XDG_RUNTIME_DIR") or "/tmp")
    lock_path = runtime / f"dropdown-screenshot-hotkey-{os.getuid()}.lock"
    with lock_path.open("w") as lock_file:
        try:
            fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return

        xdisplay = display.Display()
        extension = xdisplay.query_extension("XInputExtension")
        if not extension.present:
            raise RuntimeError("XInput2 is unavailable")
        super_keys = {
            xdisplay.keysym_to_keycode(XK.string_to_keysym(name))
            for name in ("Super_L", "Super_R")
        }
        xdisplay.screen().root.xinput_select_events(
            [(xinput.AllDevices, xinput.RawKeyPressMask | xinput.RawKeyReleaseMask)]
        )
        xdisplay.flush()

        held_super: set[int] = set()
        last_tap: float | None = None
        used_with_other_key = False
        capture: subprocess.Popen[bytes] | None = None
        previous_event: tuple[int, int, int] | None = None

        while True:
            event = xdisplay.next_event()
            if event.type != 35 or event.extension != extension.major_opcode:
                continue
            if event.evtype not in (xinput.RawKeyPress, xinput.RawKeyRelease):
                continue
            if len(event.data) < 10:
                continue

            _device, timestamp, code = struct.unpack_from("=HII", event.data)
            signature = (event.evtype, timestamp, code)
            if signature == previous_event:
                continue  # XI2 reports physical keys through slave and master devices.
            previous_event = signature

            if event.evtype == xinput.RawKeyPress:
                if code in super_keys:
                    if not held_super:
                        used_with_other_key = False
                    held_super.add(code)
                else:
                    used_with_other_key = True
                    last_tap = None
            elif code in super_keys and code in held_super:
                held_super.remove(code)
                if held_super:
                    continue
                if used_with_other_key:
                    last_tap = None
                    continue
                now = time.monotonic()
                if last_tap is not None and now - last_tap <= DOUBLE_TAP_SECONDS:
                    if capture is None or capture.poll() is not None:
                        capture = subprocess.Popen(
                            [str(SCREENSHOT), "--monitor"], start_new_session=True
                        )
                    last_tap = None
                else:
                    last_tap = now


if __name__ == "__main__":
    main()
