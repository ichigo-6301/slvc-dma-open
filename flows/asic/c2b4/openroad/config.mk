export PLATFORM = nangate45
export DESIGN_NICKNAME = $(DMA_C4_REG_DESIGN_NICKNAME)
export DESIGN_NAME = $(DMA_C4_REG_DESIGN_NAME)

# Preserve the Design Compiler compile_ultra mapping. ORFS must not synthesize
# RTL again; its internal 1_2_yosys.v staging name does not identify the tool.
export SYNTH_NETLIST_FILES = $(DMA_C4_REG_MAPPED_NETLIST)
export VERILOG_FILES =
export SDC_FILE = $(DMA_C4_REG_SDC)
export PRE_GLOBAL_ROUTE_TCL = $(DMA_C4_REG_ROOT)/flows/asic/c2b4/openroad/pre_global_route_audit.tcl

ifneq ($(strip $(DMA_C2_REG_HOLD_ECO)),)
ifeq ($(DMA_C2_REG_HOLD_ECO),dc550_pnr450_eco3)
export PRE_DETAIL_ROUTE_TCL = $(DMA_C4_REG_ROOT)/flows/asic/c2b4/openroad/pre_detail_route_hold_eco3.tcl
else
export PRE_DETAIL_ROUTE_TCL = $(DMA_C4_REG_ROOT)/flows/asic/c2b4/openroad/pre_detail_route_hold_eco.tcl
endif
endif

export CORE_UTILIZATION = 35
export CORE_ASPECT_RATIO = 1
export CORE_MARGIN = 20
export PLACE_DENSITY = 0.45
export MIN_ROUTING_LAYER = metal2
export MIN_CLK_ROUTING_LAYER = metal4
export MAX_ROUTING_LAYER = metal10
export TNS_END_PERCENT = 100
export SETUP_SLACK_MARGIN = 0.00
# CTS keeps a 60 ps guardband.  The pre-global-route audit switches the
# global-route repair target to zero so routed repair fixes real violations.
export HOLD_SLACK_MARGIN = 0.06
export CAP_MARGIN = 60
export SLEW_MARGIN = 65
export OPENROAD_THREADS = $(DMA_C4_REG_THREADS)
