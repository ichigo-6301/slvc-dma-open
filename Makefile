ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
PYTHON ?= python
FLOWCTL := $(PYTHON) flows/scripts/flowctl.py --root "$(ROOT)" --config "$(ROOT)/.config"

.RECIPEPREFIX := >
.DEFAULT_GOAL := help
.PHONY: help defconfig slvc_dma_512_defconfig showconfig sim sim-dry-run fpga-ooc fpga-ooc-dry-run

help:
> @printf '%s\n' 'SLVC DMA v0.1.0-rc1 public flow' '' '  make slvc_dma_512_defconfig' '  make showconfig' '  make sim[-dry-run]' '  make fpga-ooc[-dry-run]'

defconfig slvc_dma_512_defconfig:
> @$(FLOWCTL) defconfig --source "$(ROOT)/configs/slvc_dma_512_defconfig"

showconfig:
> @$(FLOWCTL) show-config

sim:
> @$(FLOWCTL) sim

sim-dry-run:
> @$(FLOWCTL) sim-dry-run

fpga-ooc:
> @$(FLOWCTL) fpga-ooc

fpga-ooc-dry-run:
> @$(FLOWCTL) fpga-ooc-dry-run
