ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
CONFIG ?= .config
LOCAL_CONFIG ?= flows/local/toolchain.mk

# Normalize Windows separators before classifying paths. UNC and drive paths
# stay absolute on every host; relative paths remain rooted at this checkout.
normalize_path = $(subst \,/,$(strip $(1)))
root_path = $(if $(filter //%,$(call normalize_path,$(1))),$(call normalize_path,$(1)),$(if $(findstring :,$(call normalize_path,$(1))),$(call normalize_path,$(1)),$(abspath $(if $(filter /%,$(call normalize_path,$(1))),$(call normalize_path,$(1)),$(ROOT)/$(call normalize_path,$(1))))))
CONFIG_PATH := $(call root_path,$(CONFIG))
LOCAL_CONFIG_PATH := $(call root_path,$(LOCAL_CONFIG))

-include $(CONFIG_PATH)
-include $(LOCAL_CONFIG_PATH)

DEFCONFIG ?= configs/slvc_dma_512_defconfig
PYTHON ?= python3
KCONFIG_MCONF ?= mconf
VSIM ?= vsim
VIVADO ?= vivado
VIVADO_2022_2 ?= vivado
DC_SHELL ?= dc_shell
PT_SHELL ?= pt_shell
DEFCONFIG_PATH = $(call root_path,$(DEFCONFIG))
KCONFIG_PATH := $(ROOT)/Kconfig
FLOWCTL = $(PYTHON) "$(ROOT)/flows/scripts/flowctl.py" --root "$(ROOT)" --config "$(CONFIG_PATH)"
CHECKSUM_GENERATOR = $(PYTHON) "$(ROOT)/provenance/generate_checksums.py" --root "$(ROOT)"
SHOWCASE_ASSET_GENERATOR = $(PYTHON) "$(ROOT)/flows/scripts/generate_showcase_assets.py" --root "$(ROOT)"
SHOWCASE_RENDER_CHECKER = $(PYTHON) "$(ROOT)/flows/scripts/check_showcase_render.py" --root "$(ROOT)"

export DMA_FLOW_ROOT := $(ROOT)
export DMA_FLOW_CONFIG := $(CONFIG_PATH)
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
.PHONY: help showcase-check showcase-assets-check refresh-showcase-assets public-hygiene asic-evidence-check dma-async64-throughput-check results-asset-check refresh-results-asset refresh-checksums verify-current-checksums \
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
>   '  make showcase-check               Run public integrity and interface contracts' \
>   '  make showcase-assets-check        Verify deterministic architecture/result SVGs' \
>   '  make asic-evidence-check          Validate sanitized ASIC paired-DC evidence' \
>   '  make dma-async64-throughput-check Validate the private blocked throughput experiment' \
>   '  make results-asset-check          Compatibility alias for showcase-assets-check' \
>   '  make verify-current-checksums      Verify the tracked checksum manifest' \
>   '' \
>   'Stages: sim fpga-ooc adapter-dc-ooc rx-payload-writer-dc-ooc' \
>   '        n45-c2-reg-{audit,sim,dc,pnr,sta}' \
>   '        vivado-async64-2022.2-ooc' \
>   'Utilities: n45-a5-{model,clock-delivery}-audit' \
>   'Local tools, PDKs, and libraries belong in flows/local/ (ignored).'

showcase-check: showcase-assets-check public-hygiene asic-evidence-check
> @cd "$(ROOT)" && $(PYTHON) -m unittest flows.scripts.test_flowctl_make flows.scripts.test_n45_showcase flows.scripts.test_validate_asic_evidence flows.scripts.test_validate_pr_scope_policy flows.scripts.test_generate_showcase_assets
> @printf '%s\n' 'SHOWCASE_CHECK_PASS'

public-hygiene:
> @$(PYTHON) "$(ROOT)/flows/scripts/public_hygiene.py" --root "$(ROOT)"

asic-evidence-check:
> @$(PYTHON) "$(ROOT)/flows/scripts/validate_asic_evidence.py" --root "$(ROOT)"

dma-async64-throughput-check:
> @$(PYTHON) "$(ROOT)/flows/scripts/validate_dma_async64_throughput.py" --root "$(ROOT)"
> @cd "$(ROOT)" && $(PYTHON) -m unittest flows.scripts.test_validate_dma_async64_throughput

showcase-assets-check:
> @$(SHOWCASE_ASSET_GENERATOR) --check
> @$(SHOWCASE_RENDER_CHECKER)

refresh-showcase-assets:
> @$(SHOWCASE_ASSET_GENERATOR) --write

results-asset-check: showcase-assets-check

refresh-results-asset: refresh-showcase-assets

refresh-checksums:
> @$(CHECKSUM_GENERATOR) --include-untracked

verify-current-checksums:
> @$(CHECKSUM_GENERATOR) --check

defconfig:
> @$(FLOWCTL) defconfig --source "$(DEFCONFIG_PATH)"

$(DEFCONFIG_TARGETS):
> @$(FLOWCTL) defconfig --source "$(ROOT)/configs/$@"

menuconfig:
> @test -f "$(CONFIG_PATH)" || $(FLOWCTL) defconfig --source "$(DEFCONFIG_PATH)"
> @command -v "$(KCONFIG_MCONF)" >/dev/null 2>&1 || { \
>   echo 'Kconfig frontend not found; install mconf/kconfig-frontends or set KCONFIG_MCONF.'; \
>   exit 2; \
> }
> @KCONFIG_CONFIG="$(CONFIG_PATH)" "$(KCONFIG_MCONF)" "$(KCONFIG_PATH)"

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
