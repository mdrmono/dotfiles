#!/usr/bin/python3
"""Publish a PNG from stdin to the X11 clipboard using GTK.

The Ubuntu 24.04 xclip package is based on xclip 0.13 and can hang while
serving images larger than roughly 1 MiB. GTK's clipboard implementation
handles those incremental X11 transfers correctly.
"""

from __future__ import annotations

import os
import select
import signal
import sys


READY_TIMEOUT_SECONDS = 5


def serve_clipboard(png_data: bytes, ready_fd: int) -> None:
    import gi

    gi.require_version("Gdk", "3.0")
    gi.require_version("GdkPixbuf", "2.0")
    gi.require_version("Gtk", "3.0")
    from gi.repository import Gdk, GdkPixbuf, GLib, Gtk

    loader = GdkPixbuf.PixbufLoader.new_with_type("png")
    loader.write(png_data)
    loader.close()
    pixbuf = loader.get_pixbuf()
    if pixbuf is None:
        raise RuntimeError("the screenshot is not a valid PNG")

    display = Gdk.Display.get_default()
    if display is None:
        raise RuntimeError("cannot connect to the X11 display")

    clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD)
    clipboard.set_image(pixbuf)
    display.sync()

    # Drain the ownership event created by set_image before watching for a
    # later clipboard owner. A new copy then shuts this provider down cleanly.
    while Gtk.events_pending():
        Gtk.main_iteration_do(False)

    clipboard.connect("owner-change", lambda *_args: Gtk.main_quit())
    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, Gtk.main_quit)
    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, Gtk.main_quit)

    os.write(ready_fd, b"ready")
    os.close(ready_fd)
    Gtk.main()


def publish(png_data: bytes) -> None:
    ready_read_fd, ready_write_fd = os.pipe()
    child_pid = os.fork()

    if child_pid == 0:
        os.close(ready_read_fd)
        try:
            os.setsid()
            signal.signal(signal.SIGHUP, signal.SIG_IGN)
            serve_clipboard(png_data, ready_write_fd)
        except BaseException as exc:
            try:
                os.write(ready_write_fd, f"error: {exc}".encode("utf-8", "replace"))
                os.close(ready_write_fd)
            except OSError:
                pass
            os._exit(1)
        os._exit(0)

    os.close(ready_write_fd)
    ready, _, _ = select.select([ready_read_fd], [], [], READY_TIMEOUT_SECONDS)
    if not ready:
        os.close(ready_read_fd)
        os.kill(child_pid, signal.SIGTERM)
        raise RuntimeError("timed out while taking ownership of the clipboard")

    message = os.read(ready_read_fd, 4096)
    os.close(ready_read_fd)
    if message != b"ready":
        detail = message.decode("utf-8", "replace") or "clipboard provider exited"
        raise RuntimeError(detail)


def main() -> int:
    png_data = sys.stdin.buffer.read()
    if not png_data:
        print("clipboard-image: no screenshot data received", file=sys.stderr)
        return 1

    try:
        publish(png_data)
    except (OSError, RuntimeError) as exc:
        print(f"clipboard-image: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
