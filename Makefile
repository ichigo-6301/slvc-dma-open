ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
PYTHON ?= python3
FLOWCTL := $(PYTHON) flows/scripts/flowctl.py --root "$(ROOT)" --config "$(ROOT)/.config"

.RECIPEPREFIX := >
.DEFAULT_GOAL := help
.PHONY: help defconfig slvc_dma_512_defconfig showconfig public-hygiene sim sim-dry-run fpga-ooc fpga-ooc-dry-run adapter-dc-ooc adapter-dc-ooc-dry-run

help:
> @printf '%s\n' 'SLVC DMA public flow with optional UDP/IPv4 adapter P0' '' '  make slvc_dma_512_defconfig' '  make showconfig' '  make public-hygiene' '  make sim[-dry-run]' '  make fpga-ooc[-dry-run]' '  make adapter-dc-ooc[-dry-run]'

defconfig slvc_dma_512_defconfig:
> @$(FLOWCTL) defconfig --source "$(ROOT)/configs/slvc_dma_512_defconfig"

showconfig:
> @$(FLOWCTL) show-config

public-hygiene:
> @$(PYTHON) flows/scripts/public_hygiene.py --root "$(ROOT)"

sim:
> @$(FLOWCTL) sim

sim-dry-run:
> @$(FLOWCTL) sim-dry-run

fpga-ooc:
> @$(FLOWCTL) fpga-ooc

fpga-ooc-dry-run:
> @$(FLOWCTL) fpga-ooc-dry-run

adapter-dc-ooc:
> @$(FLOWCTL) adapter-dc-ooc

adapter-dc-ooc-dry-run:
> @$(FLOWCTL) adapter-dc-ooc-dry-run
