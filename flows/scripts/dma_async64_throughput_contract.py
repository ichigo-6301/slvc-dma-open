#!/usr/bin/env python3
"""Fixed workload contract for the private Async64 throughput experiment."""

from __future__ import print_function


FRAME_COUNT = 1024
SEED = 71
CLOCK_MHZ = 100
MAIN_POINT_ID = "loopback_peak_phase3"
MIXED_FRAME_BYTES = (64, 128, 256, 1024, 4096)


def matrix_points():
    rows = []

    def add(point_id, scenario, payload_bytes, shared_service=1,
            response_latency=16, service_percent=100, mem_phase_ns=3):
        rows.append({
            "point_id": point_id,
            "scenario": scenario,
            "frames": FRAME_COUNT,
            "payload_arg_bytes": payload_bytes,
            "model": "HP0_SHARED" if shared_service else "IDEAL_SPLIT",
            "shared_service": shared_service,
            "response_latency_cycles": response_latency,
            "service_percent": service_percent,
            "mem_phase_ns": mem_phase_ns,
        })

    for phase in (1, 3, 7):
        add("rx_peak_phase{}".format(phase), "rx_peak", 4096,
            mem_phase_ns=phase)
        add("loopback_peak_phase{}".format(phase), "loopback_peak", 4096,
            mem_phase_ns=phase)
    add("rx_peak_ideal_split", "rx_peak", 4096, shared_service=0)
    add("loopback_peak_ideal_split", "loopback_peak", 4096,
        shared_service=0)
    for size in (64, 128, 256, 1024, 4096):
        add("rx_size_{}".format(size), "rx_size", size)
        add("loopback_size_{}".format(size), "loopback_size", size)
    add("mixed16", "mixed16", 4096)
    for latency in (8, 16, 32):
        for service in (100, 75, 50):
            add("hp0_l{}_s{}".format(latency, service),
                "hp0_sensitivity", 4096,
                response_latency=latency, service_percent=service)
    return rows


def correctness_ladder_points():
    return [{
        "point_id": "loopback_ladder_{}".format(frames),
        "scenario": "loopback_peak",
        "frames": frames,
        "payload_arg_bytes": 4096,
        "model": "HP0_SHARED",
        "shared_service": 1,
        "response_latency_cycles": 16,
        "service_percent": 100,
        "mem_phase_ns": 3,
    } for frames in (1, 2, 5, 32, 1024)]


def point_map():
    points = matrix_points() + correctness_ladder_points()
    return {row["point_id"]: row for row in points}


def expected_payload_bytes(point):
    frames = point["frames"]
    if point["scenario"] == "mixed16":
        complete, remainder = divmod(frames, len(MIXED_FRAME_BYTES))
        return (complete * sum(MIXED_FRAME_BYTES) +
                sum(MIXED_FRAME_BYTES[:remainder]))
    return frames * point["payload_arg_bytes"]


def payload_model_limit(point):
    if point["scenario"].startswith("rx_"):
        return 8
    if point["model"] == "IDEAL_SPLIT":
        return 8
    return 4
