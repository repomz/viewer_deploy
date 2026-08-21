#!/usr/bin/env python3
"""Small dependency-free HTTP(S) load probe for Viewer read-only endpoints."""

from __future__ import annotations

import argparse
import concurrent.futures
import http.client
import json
import math
import ssl
import statistics
import time
from dataclasses import asdict, dataclass


@dataclass
class Sample:
    status: int
    duration_ms: float
    bytes_read: int
    error: str = ""


def percentile(values: list[float], ratio: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, math.ceil(len(ordered) * ratio) - 1))
    return ordered[index]


def connection(args: argparse.Namespace) -> http.client.HTTPConnection:
    if args.tls:
        context = ssl.create_default_context()
        if args.insecure:
            context.check_hostname = False
            context.verify_mode = ssl.CERT_NONE
        return http.client.HTTPSConnection(
            args.host, args.port, timeout=args.timeout, context=context
        )
    return http.client.HTTPConnection(args.host, args.port, timeout=args.timeout)


def worker(args: argparse.Namespace, count: int) -> list[Sample]:
    samples: list[Sample] = []
    client = connection(args)
    headers = {"Accept": args.accept, "Host": args.host_header or args.host}
    if args.range_bytes:
        headers["Range"] = f"bytes=0-{args.range_bytes - 1}"
    for _ in range(count):
        started = time.perf_counter()
        try:
            client.request("GET", args.path, headers=headers)
            response = client.getresponse()
            payload = response.read()
            samples.append(
                Sample(
                    status=response.status,
                    duration_ms=(time.perf_counter() - started) * 1000,
                    bytes_read=len(payload),
                )
            )
        except Exception as error:  # noqa: BLE001 - the probe records transport failures
            samples.append(
                Sample(
                    status=0,
                    duration_ms=(time.perf_counter() - started) * 1000,
                    bytes_read=0,
                    error=str(error),
                )
            )
            try:
                client.close()
            finally:
                client = connection(args)
    client.close()
    return samples


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--host-header", default="")
    parser.add_argument("--port", type=int, default=443)
    parser.add_argument("--path", required=True)
    parser.add_argument("--requests", type=int, default=100)
    parser.add_argument("--concurrency", type=int, default=5)
    parser.add_argument("--timeout", type=float, default=20)
    parser.add_argument("--accept", default="application/json")
    parser.add_argument("--range-bytes", type=int, default=0)
    parser.add_argument("--tls", action="store_true")
    parser.add_argument("--insecure", action="store_true")
    args = parser.parse_args()

    workers = max(1, min(args.concurrency, args.requests))
    counts = [args.requests // workers] * workers
    for index in range(args.requests % workers):
        counts[index] += 1

    started = time.perf_counter()
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
        batches = list(executor.map(lambda count: worker(args, count), counts))
    elapsed = time.perf_counter() - started
    samples = [sample for batch in batches for sample in batch]
    successful = [sample for sample in samples if 200 <= sample.status < 400]
    durations = [sample.duration_ms for sample in successful]
    statuses: dict[str, int] = {}
    for sample in samples:
        key = str(sample.status) if sample.status else "transport_error"
        statuses[key] = statuses.get(key, 0) + 1

    report = {
        "path": args.path,
        "requests": len(samples),
        "concurrency": workers,
        "elapsed_seconds": round(elapsed, 3),
        "requests_per_second": round(len(samples) / elapsed, 2),
        "successful": len(successful),
        "statuses": statuses,
        "bytes_read": sum(sample.bytes_read for sample in samples),
        "latency_ms": {
            "mean": round(statistics.mean(durations), 2) if durations else 0,
            "p50": round(percentile(durations, 0.50), 2),
            "p95": round(percentile(durations, 0.95), 2),
            "p99": round(percentile(durations, 0.99), 2),
            "max": round(max(durations), 2) if durations else 0,
        },
        "errors": [asdict(sample) for sample in samples if sample.error][:5],
    }
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
