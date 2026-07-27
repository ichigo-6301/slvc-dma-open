ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
PYTHON ?= python3
FLOWCTL := $(PYTHON) flows/scripts/flowctl.py --root "$(ROOT)" --config "$(ROOT)/.config"

-include $(ROOT)/flows/local/toolchain.mk

.RECIPEPREFIX := >
.DEFAULT_GOAL := help
.PHONY: help defconfig slvc_dma_512_defconfig slvc_dma_512_rx_wide_defconfig slvc_dma_512_rx_async64_defconfig slvc_dma_512_rx_async512_defconfig showconfig public-hygiene sim sim-dry-run fpga-ooc fpga-ooc-dry-run adapter-dc-ooc adapter-dc-ooc-dry-run rx-payload-writer-dc-ooc rx-payload-writer-dc-ooc-dry-run n45-c2-reg-sim n45-c2-reg-sim-dry-run n45-c2-reg-dc n45-c2-reg-dc-dry-run n45-c2-reg-pnr n45-c2-reg-pnr-dry-run n45-c2-reg-sta n45-c2-reg-sta-dry-run n45-c2-reg-audit vivado-async64-2022.2-ooc vivado-async64-2022.2-ooc-dry-run n45-a5-model-audit n45-a5-model-audit-dry-run n45-a5-clock-delivery-audit n45-a5-clock-delivery-audit-dry-run

help:
> @printf '%s\n' 'SLVC DMA public flow' '' '  make slvc_dma_512_defconfig' '  make slvc_dma_512_rx_wide_defconfig' '  make slvc_dma_512_rx_async64_defconfig' '  make slvc_dma_512_rx_async512_defconfig' '  make showconfig' '  make public-hygiene' '  make sim[-dry-run]' '  make fpga-ooc[-dry-run]' '  make adapter-dc-ooc[-dry-run]' '  make rx-payload-writer-dc-ooc[-dry-run]' '  make n45-c2-reg-{sim,dc,pnr,sta}[-dry-run]' '  make n45-c2-reg-audit' '  make vivado-async64-2022.2-ooc[-dry-run]' '  make n45-a5-{model,clock-delivery}-audit[-dry-run]'

defconfig slvc_dma_512_defconfig:
> @$(FLOWCTL) defconfig --source "$(ROOT)/configs/slvc_dma_512_defconfig"

slvc_dma_512_rx_wide_defconfig:
> @$(FLOWCTL) defconfig --source "$(ROOT)/configs/slvc_dma_512_rx_wide_defconfig"

slvc_dma_512_rx_async64_defconfig:
> @$(FLOWCTL) defconfig --source "$(ROOT)/configs/slvc_dma_512_rx_async64_defconfig"

slvc_dma_512_rx_async512_defconfig:
> @$(FLOWCTL) defconfig --source "$(ROOT)/configs/slvc_dma_512_rx_async512_defconfig"

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

rx-payload-writer-dc-ooc:
> @$(FLOWCTL) rx-payload-writer-dc-ooc

rx-payload-writer-dc-ooc-dry-run:
> @$(FLOWCTL) rx-payload-writer-dc-ooc-dry-run

n45-c2-reg-sim n45-c2-reg-sim-dry-run n45-c2-reg-dc n45-c2-reg-dc-dry-run n45-c2-reg-pnr n45-c2-reg-pnr-dry-run n45-c2-reg-sta n45-c2-reg-sta-dry-run n45-c2-reg-audit:
> @$(FLOWCTL) $@

vivado-async64-2022.2-ooc vivado-async64-2022.2-ooc-dry-run:
> @$(FLOWCTL) $@

n45-a5-model-audit n45-a5-model-audit-dry-run n45-a5-clock-delivery-audit n45-a5-clock-delivery-audit-dry-run:
> @$(FLOWCTL) $@
