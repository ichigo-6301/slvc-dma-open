#!/usr/bin/env python3
"""Fail closed when OpenROAD drops a register-showcase physical constraint."""

import argparse
import math
import re
from pathlib import Path


def require_file(path, label):
    path = Path(path)
    if not path.is_file() or path.stat().st_size == 0:
        raise RuntimeError("missing {}: {}".format(label, path))
    return path


def normalized_commands(path):
    text = require_file(path, "roundtrip SDC").read_text(
        encoding="utf-8", errors="replace"
    )
    text = re.sub(r"\\\s*\n\s*", " ", text)
    return [line.strip() for line in text.splitlines() if line.strip()]


def command(commands, name, predicate=None):
    matches = [line for line in commands if line.startswith(name + " ")]
    if predicate is not None:
        matches = [line for line in matches if predicate(line)]
    if len(matches) != 1:
        raise RuntimeError(
            "roundtrip SDC requires exactly one {} command, found {}".format(
                name, len(matches)
            )
        )
    return matches[0]


def command_set(commands, name, expected_count):
    matches = [line for line in commands if line.startswith(name + " ")]
    if len(matches) != expected_count:
        raise RuntimeError(
            "roundtrip SDC requires {} {} commands, found {}".format(
                expected_count, name, len(matches)
            )
        )
    return matches


def number_after(line, option, label):
    match = re.search(
        r"(?:^|\s){}\s+([-+]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+))"
        .format(re.escape(option)),
        line,
    )
    if not match:
        raise RuntimeError("{} is missing from roundtrip SDC".format(label))
    value = float(match.group(1))
    if not math.isfinite(value):
        raise RuntimeError("{} is not finite".format(label))
    return value


def require_close(actual, expected, label, tolerance=1e-6):
    if abs(actual - expected) > tolerance:
        raise RuntimeError(
            "{} mismatch: expected {}, found {}".format(label, expected, actual)
        )


def port_targets(lines, label):
    targets = []
    for line in lines:
        matches = re.findall(r"\[get_ports\s+\{([^}]*)\}\]", line)
        if len(matches) != 1:
            raise RuntimeError("{} does not resolve to one port: {}".format(
                label, line
            ))
        names = matches[0].split()
        if len(names) != 1:
            raise RuntimeError("{} does not resolve to one named port".format(label))
        targets.append(names[0])
    if len(set(targets)) != len(targets):
        raise RuntimeError("{} contains duplicate ports".format(label))
    return set(targets)


def audit(args):
    if args.period_tolerance <= 0.0 or args.period_tolerance > 0.000050:
        raise RuntimeError("clock period tolerance is outside the approved window")
    commands = normalized_commands(args.sdc)
    clock = command(commands, "create_clock", lambda line: "-name a1_clk" in line)
    require_close(
        number_after(clock, "-period", "clock period"), args.period,
        "clock period", args.period_tolerance,
    )

    setup = command(
        commands, "set_clock_uncertainty", lambda line: "-setup" in line
    )
    hold = command(
        commands, "set_clock_uncertainty", lambda line: "-hold" in line
    )
    require_close(number_after(setup, "-setup", "setup uncertainty"),
                  args.setup_uncertainty, "setup uncertainty")
    require_close(number_after(hold, "-hold", "hold uncertainty"),
                  args.hold_uncertainty, "hold uncertainty")

    input_delays = command_set(
        commands, "set_input_delay", args.expected_input_count
    )
    for line in input_delays:
        require_close(number_after(line, "set_input_delay", "input delay"),
                      0.500, "input delay")
        if "a1_clk" not in line:
            raise RuntimeError("input delay is not bound to a1_clk")
    input_delay_ports = port_targets(input_delays, "input delays")
    if "clk" in input_delay_ports:
        raise RuntimeError("input delay incorrectly includes the clock port")

    input_transitions = command_set(
        commands, "set_input_transition", args.expected_input_count
    )
    for line in input_transitions:
        require_close(number_after(
            line, "set_input_transition", "input transition"
        ), 0.100, "input transition")
    if port_targets(input_transitions, "input transitions") != input_delay_ports:
        raise RuntimeError("input delay and transition port sets differ")

    output_delays = command_set(
        commands, "set_output_delay", args.expected_output_count
    )
    for line in output_delays:
        require_close(number_after(line, "set_output_delay", "output delay"),
                      0.500, "output delay")
        if "a1_clk" not in line:
            raise RuntimeError("output delay is not bound to a1_clk")
    output_delay_ports = port_targets(output_delays, "output delays")

    loads = command_set(commands, "set_load", args.expected_output_count)
    for line in loads:
        require_close(number_after(line, "-pin_load", "output load"),
                      0.050, "output load")
    if port_targets(loads, "output loads") != output_delay_ports:
        raise RuntimeError("output delay and load port sets differ")
    command(commands, "set_false_path", lambda line: "rstn" in line)

    max_fanout = command(commands, "set_max_fanout")
    require_close(number_after(max_fanout, "set_max_fanout", "max fanout"),
                  16.0, "max fanout")
    max_transition = command(commands, "set_max_transition")
    require_close(number_after(
        max_transition, "set_max_transition", "max transition"
    ), 0.500, "max transition")

    log_text = require_file(args.log, "synthesis ODB log").read_text(
        encoding="utf-8", errors="replace"
    )
    forbidden = (
        r"There are [1-9][0-9]* input ports missing set_input_delay",
        r"There are [1-9][0-9]* output ports missing set_output_delay",
        r"There are [1-9][0-9]* unconstrained endpoints",
    )
    hits = [pattern for pattern in forbidden if re.search(pattern, log_text)]
    if hits:
        raise RuntimeError(
            "OpenROAD reports incomplete physical constraints: {}".format(hits)
        )
    print(
        "DMA_C4_REGISTER_PHYSICAL_SDC_PASS period_ns={:.6f} "
        "setup_uncertainty_ns={:.3f} hold_uncertainty_ns={:.3f} "
        "nonclock_inputs={} outputs={}".format(
            args.period, args.setup_uncertainty, args.hold_uncertainty,
            args.expected_input_count, args.expected_output_count,
        )
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdc", required=True)
    parser.add_argument("--log", required=True)
    parser.add_argument("--period", type=float, required=True)
    parser.add_argument("--period-tolerance", type=float, required=True)
    parser.add_argument("--setup-uncertainty", type=float, required=True)
    parser.add_argument("--hold-uncertainty", type=float, required=True)
    parser.add_argument("--expected-input-count", type=int, required=True)
    parser.add_argument("--expected-output-count", type=int, required=True)
    args = parser.parse_args()
    audit(args)


if __name__ == "__main__":
    try:
        main()
    except RuntimeError as error:
        raise SystemExit("physical-sdc-audit: {}".format(error))
