# DMA ASIC Route A0 Floorplan Feasibility

The physical risk register is [dma_physical_risk_register.csv](data/dma_physical_risk_register.csv).

## Preconditions

- **ANALYSIS**: do not freeze die or core dimensions before actual LEF dimensions exist for every selected macro organization.
- **ANALYSIS**: require Liberty, LEF, GDS, Verilog, and compiled DB from one pinned OpenRAM configuration, plus view hashes and pin-family audit.
- **TBD_MEASUREMENT**: macro dimensions, aspect ratios, obstruction shapes, signal pin locations, clock pin capacitance, and minimum period.

## Target B Floorplan Hypothesis

```text
RX ingress / admission
        |
  [fixed payload bank groups] -- [shared pool bank group]
        |                              |
        +------ 512-bit selector ------+
                       |
              [optional CDC FIFO]
                       |
               [512-bit AXI writer]
                       |
                RX AXI boundary
```

- **ASSUMPTION**: place each four-macro width-bank quartet as one logical cluster so a 512-bit word does not cross the core.
- **ASSUMPTION**: place four fixed-ingress depth groups adjacent to the selector and writer, with the depth decode/read-select registers at the bank boundary.
- **ASSUMPTION**: place shared-pool data and its keep/control registers together, but keep free-list and metadata control in standard cells beside the pool FSM.
- **ANALYSIS**: for Async512, place the source-domain side of the payload FIFO near source stores and the memory-domain reader/writer near the RX AXI boundary. Do not scatter width banks across clock regions.

## Target C Regional Partition

- **ASSUMPTION**: RX storage and admission occupy one region; the RX512 writer sits between storage and the memory-facing edge.
- **ASSUMPTION**: TX descriptor/read-prefetch and its 64-bit AXI boundary occupy a separate region to avoid dragging 512-bit TX stream data through RX macro channels.
- **ASSUMPTION**: CQ and AXI write arbitration sit near the shared 64-bit memory boundary; AXI-Lite/channel tables sit near the control-side ports.
- **ANALYSIS**: optional carrier CDC/MCF should be a separate partition or excluded from the first full-DMA physical target.

## Utilization And Routing Rules

- **ASSUMPTION**: begin macro-heavy Target B at roughly 40-50% standard-cell placement density after subtracting macro area; begin logic-only Target A around 50-60%.
- **ANALYSIS**: these are bring-up ranges, not final utilization targets. First close legal placement and route, then sweep density and frequency.
- **ANALYSIS**: derive halo and channel spacing from actual pin density and route trials; do not copy MRTC's fixed numbers.
- **ANALYSIS**: orient macro data pins toward the consuming mux/register boundary where the generated LEF permits it.
- **ANALYSIS**: reserve horizontal/vertical channels for 512 data bits, 64 keep bits, address/control, and test/power access.

## Clock And Reset Placement

- **ANALYSIS**: Profile C needs separate `aclk` and `mem_clk` CTS trees with synchronizers placed close to destination-domain clock roots and first-stage sinks.
- **ANALYSIS**: Gray pointer bits in one bus should have matched physical treatment; bus-skew constraints must survive placement and route.
- **ANALYSIS**: high-fanout reset/quiesce/enable nets require planned buffering and local replication based on reports, not RTL-wide asynchronous reset expansion.
- **ANALYSIS**: hold repair risk is elevated around short synchronizer/status paths and macro boundary registers; retain separate setup and hold guardbands.

## Power And Macro Integration

- **VERIFIED_REPOSITORY_FACT**: the MRTC Nangate45 flow needed a pre-PDN mapping from OpenRAM `vdd/gnd` to platform `VDD/VSS`.
- **ANALYSIS**: DMA can reuse that method, but each new macro's supply pins and obstruction geometry must be audited independently.
- **ANALYSIS**: power straps must cross or ring macro clusters without blocking dense 512-bit signal pins.
- **TBD_MEASUREMENT**: IR drop, current density, macro power, decap need, and final PG topology.

## Bring-Up Sequence

1. **ANALYSIS**: import mapped netlist and all macro views; assert exact macro count and no overlap.
2. **ANALYSIS**: place macros only, then run pin-access/global-route feasibility before standard-cell optimization.
3. **ANALYSIS**: complete placement and congestion review at conservative density.
4. **ANALYSIS**: add CTS and audit setup/hold path classes before aggressive repair.
5. **ANALYSIS**: require detailed route, antenna, final SPEF, and matching PrimeTime handoff before any physical timing claim.

