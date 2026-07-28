ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
CONFIG ?= .config
DEFCONFIG ?= configs/slvc_dma_512_defconfig
LOCAL_CONFIG ?= flows/local/toolchain.mk
PYTHON ?= python3
KCONFIG_MCONF ?= mconf
FLOWCTL := $(PYTHON) flows/scripts/flowctl.py --root "$(ROOT)" --config "$(CONFIG)"

-include $(CONFIG)
-include $(LOCAL_CONFIG)

export DMA_FLOW_ROOT := $(ROOT)
export DMA_FLOW_CONFIG := $(abspath $(CONFIG))
export PYTHON VSIM VIVADO VIVADO_2022_2 DC_SHELL PT_SHELL
export DMA_DC_TARGET_LIBRARY DMA_N45_STDCELL_DB DMA_N45_LIBERTY DMA_ORFS_ROOT
export DMA_C2_BUILD_ROOT DMA_C2_MAPPED_NETLIST DMA_C2_ALLOW_UNMEASURED_ROUTE
export DMA_C2_DESIGN_NAME DMA_DC_MAX_CORES DMA_A5_512_LIBERTY
export DMA_A5_CLOCK_AUDIT_REPORT REPORT_TAG

FLOW_STAGES := sim fpga-ooc adapter-dc-ooc rx-payload-writer-dc-ooc \
               n45-c2-reg-audit n45-c2-reg-sim n45-c2-reg-dc \
               n45-c2-reg-pnr n45-c2-reg-sta \
               vivado-async64-2022.2-ooc \
               n45-a5-model-audit n45-a5-clock-delivery-audit
DRY_RUN_STAGES := $(filter-out n45-c2-reg-audit,$(FLOW_STAGES))
DRY_RUN_TARGETS := $(addsuffix -dry-run,$(DRY_RUN_STAGES))
DEFCONFIG_TARGETS := slvc_dma_512_core_only_defconfig \
                     slvc_dma_512_defconfig \
                     slvc_dma_512_rx_wide_defconfig \
                     slvc_dma_512_rx_async64_defconfig \
                     slvc_dma_512_rx_async512_defconfig \
                     dma_rx512_reg_c2_b4_m2_sp64_defconfig

.RECIPEPREFIX := >
.DEFAULT_GOAL := help
.PHONY: help showcase-check public-hygiene \
        defconfig $(DEFCONFIG_TARGETS) menuconfig showconfig validate-profile \
        list-stages selected selected-dry-run $(FLOW_STAGES) $(DRY_RUN_TARGETS)

help:
> @printf '%s\n' \
>   'SLVC DMA public implementation flow' \
>   '' \
>   '  make slvc_dma_512_defconfig       Select the public 512-bit profile' \
>   '  make <profile>_defconfig          Select a tracked implementation profile' \
>   '  make menuconfig                   Edit .config with a Kconfig frontend' \
>   '  make showconfig                   Display profile, backend, and enabled stages' \
>   '  make validate-profile             Validate the selected configuration' \
>   '  make list-stages                  List stages and controlling config symbols' \
>   '  make <stage>-dry-run              Print one bounded tool invocation' \
>   '  make <stage>                      Run one enabled stage' \
>   '  make selected[-dry-run]           Run enabled stages in dependency order' \
>   '  make showcase-check               Run public integrity and flow contracts' \
>   '' \
>   'Stages: sim fpga-ooc adapter-dc-ooc rx-payload-writer-dc-ooc' \
>   '        n45-c2-reg-{audit,sim,dc,pnr,sta}' \
>   '        vivado-async64-2022.2-ooc' \
>   'Utilities: n45-a5-{model,clock-delivery}-audit' \
>   'Local tools, PDKs, and libraries belong in flows/local/ (ignored).'

showcase-check: public-hygiene
> @$(PYTHON) -m unittest flows.scripts.test_n45_showcase
> @printf '%s\n' 'SHOWCASE_CHECK_PASS'

public-hygiene:
> @$(PYTHON) flows/scripts/public_hygiene.py --root "$(ROOT)"

defconfig:
> @$(FLOWCTL) defconfig --source "$(DEFCONFIG)"

$(DEFCONFIG_TARGETS):
> @$(FLOWCTL) defconfig --source "$(ROOT)/configs/$@"

menuconfig:
> @test -f "$(CONFIG)" || $(FLOWCTL) defconfig --source "$(DEFCONFIG)"
> @command -v "$(KCONFIG_MCONF)" >/dev/null 2>&1 || { \
>   echo 'Kconfig frontend not found; install mconf/kconfig-frontends or set KCONFIG_MCONF.'; \
>   exit 2; \
> }
> @KCONFIG_CONFIG="$(abspath $(CONFIG))" "$(KCONFIG_MCONF)" Kconfig

showconfig:
> @$(FLOWCTL) show-config

validate-profile:
> @$(FLOWCTL) validate-config

list-stages:
> @$(FLOWCTL) list-stages

selected:
> @$(FLOWCTL) run-selected

selected-dry-run:
> @$(FLOWCTL) run-selected --dry-run

$(FLOW_STAGES):
> @$(FLOWCTL) run --stage "$@"

$(DRY_RUN_TARGETS):
> @$(FLOWCTL) run --stage "$(patsubst %-dry-run,%,$@)" --dry-run
