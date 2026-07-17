#!/usr/bin/env bash
set -euo pipefail

: "${DMA_DC_TARGET_LIBRARY:?set DMA_DC_TARGET_LIBRARY to a local .db file}"

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$SCRIPT_DIR"
mkdir -p ../../build/dc_udp_to_shdr_ooc
dc_shell -f run_udp_to_shdr_ooc.tcl | tee ../../build/dc_udp_to_shdr_ooc/dc_shell.log
