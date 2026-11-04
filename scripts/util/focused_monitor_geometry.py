#!/usr/bin/python3
"""Print the X11 rectangle of the i3 output holding the focused workspace."""

from __future__ import annotations

import json
import subprocess


def i3_state(message_type: str) -> list[dict]:
    result = subprocess.run(
        ["i3-msg", "-t", message_type],
        capture_output=True,
        text=True,
        check=True,
        timeout=2,
    )
    return json.loads(result.stdout)


def main() -> None:
    workspace = next(item for item in i3_state("get_workspaces") if item["focused"])
    output = next(
        item
        for item in i3_state("get_outputs")
        if item["active"] and item["name"] == workspace["output"]
    )
    rect = output["rect"]
    if rect["width"] <= 0 or rect["height"] <= 0:
        raise ValueError("focused output has no capture area")
    print(f'{rect["x"]},{rect["y"]},{rect["width"]},{rect["height"]}')


if __name__ == "__main__":
    main()
