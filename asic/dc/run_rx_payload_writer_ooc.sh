#!/usr/bin/env bash
set -euo pipefail

: "${DMA_DC_TARGET_LIBRARY:?set DMA_DC_TARGET_LIBRARY to a local .db file}"
: "${DMA_DC_WRITER_PROFILE:=wide512}"
: "${DMA_DC_CLOCK_PERIOD_NS:=5.000}"

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$SCRIPT_DIR"
export DMA_DC_WRITER_PROFILE DMA_DC_CLOCK_PERIOD_NS
dc_shell -f run_rx_payload_writer_ooc.tcl
