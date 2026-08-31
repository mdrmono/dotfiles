#!/usr/bin/env python3
"""Benchmark Minecraft latency through several PIA WireGuard regions.

The script deliberately reconnects PIA for every candidate region. It measures
the active tunnel, the resolved Minecraft edge, and the Minecraft status/pong
protocol before restoring the original PIA region and connection state.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import os
from pathlib import Path
import re
import shutil
import signal
import socket
import statistics
import struct
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime
from typing import Sequence


DEFAULT_REGIONS = (
    "us-florida",
    "us-atlanta",
    "us-houston",
    "us-chicago",
    "panama",
    "colombia",
    "peru",
    "chile",
)


@dataclass(frozen=True)
class CommandResult:
    returncode: int
    stdout: str
    stderr: str


@dataclass(frozen=True)
class PingResult:
    average_ms: float | None
    jitter_ms: float | None
    loss_percent: float | None


@dataclass
class RegionResult:
    region: str
    vpn_ip: str = ""
    resolved_ip: str = ""
    gateway_average_ms: float | None = None
    gateway_loss_percent: float | None = None
    edge_average_ms: float | None = None
    edge_jitter_ms: float | None = None
    edge_loss_percent: float | None = None
    tcp_samples_ms: list[float] | None = None
    status_samples_ms: list[float] | None = None
    pong_samples_ms: list[float] | None = None
    attempted_samples: int = 0
    errors: list[str] | None = None

    def __post_init__(self) -> None:
        self.tcp_samples_ms = [] if self.tcp_samples_ms is None else self.tcp_samples_ms
        self.status_samples_ms = (
            [] if self.status_samples_ms is None else self.status_samples_ms
        )
        self.pong_samples_ms = (
            [] if self.pong_samples_ms is None else self.pong_samples_ms
        )
        self.errors = [] if self.errors is None else self.errors

    @property
    def successful_samples(self) -> int:
        return len(self.pong_samples_ms or [])

    @property
    def success_rate(self) -> float:
        if self.attempted_samples == 0:
            return 0.0
        return self.successful_samples / self.attempted_samples

    @property
    def score(self) -> float:
        """Lower is better; failed probes and packet loss are heavily penalized."""
        pong_median = median_or_none(self.pong_samples_ms or [])
        if pong_median is None:
            return math.inf
        timeout_penalty = (1.0 - self.success_rate) * 1_000.0
        loss_penalty = (self.edge_loss_percent or 0.0) * 10.0
        return pong_median + timeout_penalty + loss_penalty


def run_command(
    command: Sequence[str], *, timeout_seconds: float = 30, check: bool = False
) -> CommandResult:
    environment = os.environ.copy()
    environment["LC_ALL"] = "C"
    try:
        completed = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
            env=environment,
            check=False,
        )
    except subprocess.TimeoutExpired as error:
        raise RuntimeError(f"Command timed out: {' '.join(command)}") from error

    result = CommandResult(
        completed.returncode,
        completed.stdout.strip(),
        completed.stderr.strip(),
    )
    if check and result.returncode != 0:
        detail = result.stderr or result.stdout or f"exit {result.returncode}"
        raise RuntimeError(f"{' '.join(command)}: {detail}")
    return result


def pia_get(setting: str) -> str:
    return run_command(
        ["piactl", "get", setting], timeout_seconds=10, check=True
    ).stdout.strip()


def wait_for_pia_state(expected: str, timeout_seconds: float = 60) -> None:
    deadline = time.monotonic() + timeout_seconds
    last_state = "unknown"
    while time.monotonic() < deadline:
        try:
            last_state = pia_get("connectionstate")
        except RuntimeError:
            last_state = "unavailable"
        if last_state == expected:
            return
        time.sleep(1)
    raise RuntimeError(
        f"PIA did not reach {expected} within {timeout_seconds:.0f}s "
        f"(last state: {last_state})"
    )


def disconnect_pia() -> None:
    if pia_get("connectionstate") == "Disconnected":
        return
    run_command(["piactl", "disconnect"], timeout_seconds=20, check=True)
    wait_for_pia_state("Disconnected")


def connect_pia_region(region: str, settle_seconds: float) -> None:
    disconnect_pia()
    run_command(["piactl", "set", "region", region], timeout_seconds=15, check=True)
    run_command(["piactl", "connect"], timeout_seconds=20, check=True)
    wait_for_pia_state("Connected")

    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if pia_get("region") == region:
            break
        time.sleep(1)
    else:
        raise RuntimeError(f"PIA connected, but not to requested region {region}")

    time.sleep(settle_seconds)


def restore_pia(region: str, should_connect: bool) -> None:
    print(f"\nRestoring PIA region {region!r}...", flush=True)
    disconnect_pia()
    run_command(["piactl", "set", "region", region], timeout_seconds=15, check=True)
    if should_connect:
        run_command(["piactl", "connect"], timeout_seconds=20, check=True)
        wait_for_pia_state("Connected")
    print(
        f"PIA restored: {pia_get('connectionstate')} / {pia_get('region')}",
        flush=True,
    )


def parse_ping(output: str) -> PingResult:
    loss_match = re.search(r"([0-9]+(?:\.[0-9]+)?)% packet loss", output)
    timing_match = re.search(
        r"(?:rtt|round-trip)[^=]*=\s*"
        r"([0-9.]+)/([0-9.]+)/([0-9.]+)/([0-9.]+)\s*ms",
        output,
    )
    return PingResult(
        average_ms=float(timing_match.group(2)) if timing_match else None,
        jitter_ms=float(timing_match.group(4)) if timing_match else None,
        loss_percent=float(loss_match.group(1)) if loss_match else None,
    )


def measure_ping(destination: str, count: int) -> PingResult:
    result = run_command(
        [
            "ping",
            "-n",
            "-q",
            "-c",
            str(count),
            "-W",
            "2",
            destination,
        ],
        timeout_seconds=max(10, count * 3),
    )
    return parse_ping("\n".join((result.stdout, result.stderr)))


def find_tunnel_gateway() -> str | None:
    result = run_command(
        ["ip", "-4", "route", "show", "table", "all", "dev", "wgpia0"],
        timeout_seconds=5,
    )
    candidates: list[str] = []
    for line in result.stdout.splitlines():
        match = re.match(r"^(\d+\.\d+\.\d+\.\d+)(?:/\d+)?\s", line)
        if match:
            candidates.append(match.group(1))
    return next((address for address in candidates if address.endswith(".1")), None)


def resolve_ipv4(host: str, port: int) -> str:
    addresses = {
        entry[4][0]
        for entry in socket.getaddrinfo(host, port, socket.AF_INET, socket.SOCK_STREAM)
    }
    if not addresses:
        raise RuntimeError(f"No IPv4 address returned for {host}")
    return sorted(addresses)[0]


def encode_varint(value: int) -> bytes:
    value &= 0xFFFFFFFF
    encoded = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            byte |= 0x80
        encoded.append(byte)
        if not value:
            return bytes(encoded)


def read_exact(connection: socket.socket, length: int) -> bytes:
    chunks = bytearray()
    while len(chunks) < length:
        chunk = connection.recv(length - len(chunks))
        if not chunk:
            raise ConnectionError("Minecraft server closed the connection")
        chunks.extend(chunk)
    return bytes(chunks)


def read_varint(connection: socket.socket) -> int:
    value = 0
    for position in range(5):
        byte = read_exact(connection, 1)[0]
        value |= (byte & 0x7F) << (7 * position)
        if not byte & 0x80:
            return value
    raise ValueError("Minecraft VarInt exceeded five bytes")


def encode_string(value: str) -> bytes:
    encoded = value.encode("utf-8")
    return encode_varint(len(encoded)) + encoded


def encode_packet(packet_id: int, payload: bytes = b"") -> bytes:
    body = encode_varint(packet_id) + payload
    return encode_varint(len(body)) + body


def minecraft_probe(
    host: str, resolved_ip: str, port: int, timeout_seconds: float
) -> dict[str, float]:
    connection_started = time.perf_counter()
    with socket.create_connection(
        (resolved_ip, port), timeout=timeout_seconds
    ) as connection:
        connection.settimeout(timeout_seconds)
        tcp_ms = (time.perf_counter() - connection_started) * 1_000

        handshake_payload = b"".join(
            (
                encode_varint(-1),
                encode_string(host),
                struct.pack(">H", port),
                encode_varint(1),
            )
        )
        status_started = time.perf_counter()
        connection.sendall(encode_packet(0, handshake_payload))
        connection.sendall(encode_packet(0))

        _status_packet_length = read_varint(connection)
        if read_varint(connection) != 0:
            raise ValueError("Unexpected Minecraft status packet ID")
        status_length = read_varint(connection)
        status_payload = read_exact(connection, status_length)
        json.loads(status_payload.decode("utf-8"))
        status_ms = (time.perf_counter() - status_started) * 1_000

        nonce = time.time_ns() // 1_000_000
        pong_started = time.perf_counter()
        connection.sendall(encode_packet(1, struct.pack(">q", nonce)))
        _pong_packet_length = read_varint(connection)
        if read_varint(connection) != 1:
            raise ValueError("Unexpected Minecraft pong packet ID")
        returned_nonce = struct.unpack(">q", read_exact(connection, 8))[0]
        if returned_nonce != nonce:
            raise ValueError("Minecraft pong returned a different nonce")
        pong_ms = (time.perf_counter() - pong_started) * 1_000

    return {
        "tcp_ms": tcp_ms,
        "status_ms": status_ms,
        "pong_ms": pong_ms,
    }


def median_or_none(samples: Sequence[float]) -> float | None:
    return statistics.median(samples) if samples else None


def percentile_or_none(samples: Sequence[float], percentile: float) -> float | None:
    if not samples:
        return None
    ordered = sorted(samples)
    index = max(0, math.ceil(percentile * len(ordered)) - 1)
    return ordered[index]


def display_number(value: float | None, decimals: int = 1) -> str:
    return "-" if value is None else f"{value:.{decimals}f}"


def benchmark_region(
    region: str,
    *,
    host: str,
    port: int,
    samples: int,
    ping_count: int,
    timeout_seconds: float,
    settle_seconds: float,
    raw_rows: list[dict[str, object]],
) -> RegionResult:
    print(f"\n[{region}] Connecting...", flush=True)
    result = RegionResult(region=region, attempted_samples=samples)

    try:
        connect_pia_region(region, settle_seconds)
        result.vpn_ip = pia_get("vpnip")
        result.resolved_ip = resolve_ipv4(host, port)
        gateway = find_tunnel_gateway()

        if gateway:
            gateway_ping = measure_ping(gateway, ping_count)
            result.gateway_average_ms = gateway_ping.average_ms
            result.gateway_loss_percent = gateway_ping.loss_percent

        edge_ping = measure_ping(result.resolved_ip, ping_count)
        result.edge_average_ms = edge_ping.average_ms
        result.edge_jitter_ms = edge_ping.jitter_ms
        result.edge_loss_percent = edge_ping.loss_percent

        print(
            "  edge "
            f"{result.resolved_ip}: {display_number(result.edge_average_ms)} ms, "
            f"{display_number(result.edge_loss_percent)}% loss",
            flush=True,
        )

        for attempt in range(1, samples + 1):
            raw_row: dict[str, object] = {
                "region": region,
                "attempt": attempt,
                "vpn_ip": result.vpn_ip,
                "resolved_ip": result.resolved_ip,
                "tcp_ms": "",
                "status_ms": "",
                "pong_ms": "",
                "error": "",
            }
            try:
                sample = minecraft_probe(
                    host, result.resolved_ip, port, timeout_seconds
                )
                result.tcp_samples_ms.append(sample["tcp_ms"])
                result.status_samples_ms.append(sample["status_ms"])
                result.pong_samples_ms.append(sample["pong_ms"])
                raw_row.update(sample)
                print(
                    f"  probe {attempt}/{samples}: "
                    f"TCP {sample['tcp_ms']:.1f} ms, "
                    f"status {sample['status_ms']:.1f} ms, "
                    f"pong {sample['pong_ms']:.1f} ms",
                    flush=True,
                )
            except (OSError, ValueError, json.JSONDecodeError) as error:
                message = f"{type(error).__name__}: {error}"
                result.errors.append(message)
                raw_row["error"] = message
                print(f"  probe {attempt}/{samples}: {message}", flush=True)
            raw_rows.append(raw_row)
            time.sleep(0.75)
    except (OSError, RuntimeError) as error:
        message = f"{type(error).__name__}: {error}"
        result.errors.append(message)
        print(f"  region failed: {message}", flush=True)

    return result


def write_results(
    output_path: Path,
    ranked_results: Sequence[RegionResult],
    raw_rows: Sequence[dict[str, object]],
) -> tuple[Path, Path]:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    samples_path = output_path.with_name(f"{output_path.stem}-samples.csv")

    summary_fields = (
        "rank",
        "region",
        "vpn_ip",
        "resolved_ip",
        "gateway_average_ms",
        "gateway_loss_percent",
        "edge_average_ms",
        "edge_jitter_ms",
        "edge_loss_percent",
        "successful_samples",
        "attempted_samples",
        "tcp_median_ms",
        "status_median_ms",
        "pong_median_ms",
        "pong_p95_ms",
        "score",
        "errors",
    )
    with output_path.open("w", newline="", encoding="utf-8") as output_file:
        writer = csv.DictWriter(
            output_file, fieldnames=summary_fields, lineterminator="\n"
        )
        writer.writeheader()
        for rank, result in enumerate(ranked_results, start=1):
            writer.writerow(
                {
                    "rank": rank,
                    "region": result.region,
                    "vpn_ip": result.vpn_ip,
                    "resolved_ip": result.resolved_ip,
                    "gateway_average_ms": display_number(
                        result.gateway_average_ms, 3
                    ),
                    "gateway_loss_percent": display_number(
                        result.gateway_loss_percent, 3
                    ),
                    "edge_average_ms": display_number(result.edge_average_ms, 3),
                    "edge_jitter_ms": display_number(result.edge_jitter_ms, 3),
                    "edge_loss_percent": display_number(
                        result.edge_loss_percent, 3
                    ),
                    "successful_samples": result.successful_samples,
                    "attempted_samples": result.attempted_samples,
                    "tcp_median_ms": display_number(
                        median_or_none(result.tcp_samples_ms), 3
                    ),
                    "status_median_ms": display_number(
                        median_or_none(result.status_samples_ms), 3
                    ),
                    "pong_median_ms": display_number(
                        median_or_none(result.pong_samples_ms), 3
                    ),
                    "pong_p95_ms": display_number(
                        percentile_or_none(result.pong_samples_ms, 0.95), 3
                    ),
                    "score": display_number(
                        None if math.isinf(result.score) else result.score, 3
                    ),
                    "errors": " | ".join(result.errors),
                }
            )

    raw_fields = (
        "region",
        "attempt",
        "vpn_ip",
        "resolved_ip",
        "tcp_ms",
        "status_ms",
        "pong_ms",
        "error",
    )
    with samples_path.open("w", newline="", encoding="utf-8") as output_file:
        writer = csv.DictWriter(
            output_file, fieldnames=raw_fields, lineterminator="\n"
        )
        writer.writeheader()
        writer.writerows(raw_rows)

    return output_path, samples_path


def print_ranking(results: Sequence[RegionResult]) -> None:
    print("\nRanked by Minecraft pong, failures, and packet loss:\n")
    print(
        f"{'#':>2}  {'region':<14} {'success':>7} {'edge':>9} "
        f"{'TCP':>9} {'status':>9} {'pong':>9} {'p95':>9}"
    )
    for rank, result in enumerate(results, start=1):
        print(
            f"{rank:>2}  {result.region:<14} "
            f"{result.successful_samples:>2}/{result.attempted_samples:<4} "
            f"{display_number(result.edge_average_ms):>7}ms "
            f"{display_number(median_or_none(result.tcp_samples_ms)):>7}ms "
            f"{display_number(median_or_none(result.status_samples_ms)):>7}ms "
            f"{display_number(median_or_none(result.pong_samples_ms)):>7}ms "
            f"{display_number(percentile_or_none(result.pong_samples_ms, 0.95)):>7}ms"
        )


def default_output_path() -> Path:
    repository_root = Path(__file__).resolve().parents[2]
    timestamp = datetime.now().astimezone().strftime("%Y%m%d-%H%M%S")
    return repository_root / "output" / "network" / (
        f"pia-minecraft-benchmark-{timestamp}.csv"
    )


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Cycle through PIA WireGuard regions and rank them using actual "
            "Minecraft status/pong latency."
        )
    )
    parser.add_argument("--host", default="mc.hypixel.net")
    parser.add_argument("--port", type=int, default=25565)
    parser.add_argument("--samples", type=int, default=5)
    parser.add_argument("--ping-count", type=int, default=8)
    parser.add_argument("--timeout", type=float, default=4.0)
    parser.add_argument("--settle-seconds", type=float, default=8.0)
    parser.add_argument(
        "--regions",
        nargs="+",
        default=list(DEFAULT_REGIONS),
        help="PIA region IDs to test",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Summary CSV path; defaults to output/network/ in the dotfiles repo",
    )
    parser.add_argument(
        "--yes",
        action="store_true",
        help="Skip the interactive TEST confirmation",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show the test plan without changing PIA or creating results",
    )
    parser.add_argument(
        "--list-regions",
        action="store_true",
        help="List PIA region IDs without changing the connection",
    )
    arguments = parser.parse_args()
    if arguments.samples < 1 or arguments.ping_count < 1:
        parser.error("--samples and --ping-count must be positive")
    if not 1 <= arguments.port <= 65535:
        parser.error("--port must be between 1 and 65535")
    if arguments.timeout <= 0 or arguments.settle_seconds < 0:
        parser.error("timeouts must be positive")
    return arguments


def require_program(program: str) -> None:
    if shutil.which(program) is None:
        raise RuntimeError(f"Required command is not installed: {program}")


def warp_is_connected() -> bool:
    if shutil.which("warp-cli") is None:
        return False
    result = run_command(
        ["warp-cli", "--accept-tos", "status"], timeout_seconds=5
    )
    return "Status update: Connected" in result.stdout


def raise_interrupt(_signal_number: int, _frame: object) -> None:
    raise KeyboardInterrupt


def main() -> int:
    arguments = parse_arguments()
    for program in ("piactl", "ping", "ip"):
        require_program(program)

    available_regions = set(pia_get("regions").splitlines())
    if arguments.list_regions:
        print("\n".join(sorted(available_regions)))
        return 0

    invalid_regions = [
        region for region in arguments.regions if region not in available_regions
    ]
    if invalid_regions:
        raise RuntimeError(f"Unknown PIA region(s): {', '.join(invalid_regions)}")

    original_state = pia_get("connectionstate")
    original_region = pia_get("region")
    protocol = pia_get("protocol")
    should_restore_connection = original_state not in {
        "Disconnected",
        "Disconnecting",
    }

    if protocol != "wireguard":
        raise RuntimeError(
            f"PIA protocol is {protocol!r}; switch to WireGuard before benchmarking"
        )
    if warp_is_connected():
        raise RuntimeError("Cloudflare WARP is connected; disconnect it before testing")

    output_path = arguments.output or default_output_path()
    print("PIA Minecraft route benchmark")
    print(f"Target: {arguments.host}:{arguments.port}")
    print(f"Original PIA state: {original_state} / {original_region} / {protocol}")
    print(f"Regions: {', '.join(arguments.regions)}")
    print(f"Minecraft probes per region: {arguments.samples}")
    print(f"Results: {output_path}")
    print("The internet connection will drop during every region change.")

    if arguments.dry_run:
        print("Dry run complete; no connection changes or files were made.")
        return 0

    if not arguments.yes:
        try:
            confirmation = input("Type TEST to begin, or press Enter to cancel: ")
        except EOFError:
            confirmation = ""
        if confirmation != "TEST":
            print("Cancelled; PIA was not changed.")
            return 0

    for handled_signal in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(handled_signal, raise_interrupt)

    results: list[RegionResult] = []
    raw_rows: list[dict[str, object]] = []
    interrupted = False

    try:
        for region in arguments.regions:
            results.append(
                benchmark_region(
                    region,
                    host=arguments.host,
                    port=arguments.port,
                    samples=arguments.samples,
                    ping_count=arguments.ping_count,
                    timeout_seconds=arguments.timeout,
                    settle_seconds=arguments.settle_seconds,
                    raw_rows=raw_rows,
                )
            )
    except KeyboardInterrupt:
        interrupted = True
        print("\nBenchmark interrupted; preserving partial results.", flush=True)
    finally:
        try:
            restore_pia(original_region, should_restore_connection)
        except (OSError, RuntimeError) as error:
            print(f"WARNING: PIA restoration failed: {error}", file=sys.stderr)
            print(
                f"Restore manually with: piactl set region {original_region}",
                file=sys.stderr,
            )

    if not results:
        print("No region produced a result.", file=sys.stderr)
        return 130 if interrupted else 1

    ranked_results = sorted(results, key=lambda result: result.score)
    print_ranking(ranked_results)
    summary_path, samples_path = write_results(output_path, ranked_results, raw_rows)
    print(f"\nSummary CSV: {summary_path}")
    print(f"Sample CSV:  {samples_path}")
    if ranked_results[0].successful_samples:
        print(f"Best measured region: {ranked_results[0].region}")

    return 130 if interrupted else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1) from error
