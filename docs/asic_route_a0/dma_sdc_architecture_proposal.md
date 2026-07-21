# DMA ASIC Route A0 SDC Architecture Proposal

## Scope

- **ANALYSIS**: this document proposes constraint architecture only. No current SDC is modified.
- **VERIFIED_REPOSITORY_FACT**: the existing RX payload DC OOC script creates `s_clk` and `mem_clk`, applies an asynchronous clock group, input/output delays, and broad reset false paths. It is an OOC writer/bridge constraint, not a full-DMA signoff SDC.
- **VERIFIED_REPOSITORY_FACT**: the FPGA async flow deliberately avoids a blanket asynchronous clock group because it would override project Gray-bus max-delay constraints.

## SDC Layers

1. **ANALYSIS**: `design_base.sdc` defines clocks, propagated/generated-clock policy, reset treatment, global transition/capacitance limits, and common helper procedures.
2. **ANALYSIS**: `profile_sameclk_rx512.sdc` binds only `aclk` and Target B boundary delays.
3. **ANALYSIS**: `profile_async_rx512.sdc` adds `mem_clk`, exact CDC exceptions, Gray max-delay/bus-skew, and reset-toggle constraints.
4. **ANALYSIS**: `profile_full_rx512.sdc` adds SoC IO delays and any approved external carrier clocks.
5. **ANALYSIS**: tool adapters may translate syntax, but every stage must hash and audit the same logical constraint set.

## Real Clocks

- **ASSUMPTION**: Profile B starts with one real `aclk`; Profile C uses independent real `aclk` and `mem_clk`.
- **ANALYSIS**: clock periods are profile inputs, not constants embedded in Tcl.
- **ANALYSIS**: `tx_axis_aclk` must not be declared as an internal functional clock while RTL ignores it. Resolve the interface contract first.
- **TBD_MEASUREMENT**: propagated clock insertion delay, uncertainty, source latency, and macro clock checks.

## Asynchronous Clock Policy

- **ANALYSIS**: do not apply a blanket `set_clock_groups -asynchronous` if the implementation tool gives it precedence over Gray-bus datapath constraints.
- **ANALYSIS**: enumerate non-Gray crossing endpoints and false-path only the intended synchronizer/status/toggle destinations.
- **ANALYSIS**: preserve timing checks from each source Gray register to the first destination synchronizer stage using `set_max_delay -datapath_only` bounded by the faster source/destination period and `set_bus_skew` with the same or tighter reviewed bound.
- **ANALYSIS**: require scripts to fail closed when expected FIFO instances, pointer bits, or synchronizer stages are missing.

## FIFO Data And Memory Arcs

- **ANALYSIS**: wide FIFO data is not a bank of independent synchronizers. It is dual-port storage whose ownership crosses through Gray pointers.
- **ANALYSIS**: time write-port paths within `aclk` and read-port paths within `mem_clk`; do not time a combinational data path directly from source-domain write registers to destination-domain read registers.
- **ANALYSIS**: any CDC waiver must bind exact memory data pins and exact FIFO instances, with pointer/empty/full proof still active.
- **TBD_MEASUREMENT**: generated macro Liberty behavior for unrelated clocks and cross-port checks.

## IO Delay Profiles

- **ANALYSIS**: Target A/B internal-only bring-up may use explicit virtual clocks and conservative boundary delays, clearly labeled OOC.
- **ANALYSIS**: Profile D requires SoC integration assumptions for shared link, AXI4, AXI4-Lite, IRQ, and UFC. Do not report IO closure until those delays and driving/load models are frozen.
- **ANALYSIS**: internal-only reg-to-reg coverage and IO timing coverage must be reported separately.

## Reset Recovery And Removal

- **ANALYSIS**: preserve recovery/removal checks on asynchronously reset sequential cells and reset synchronizers.
- **ANALYSIS**: if reset data-path false paths are needed, target data pins or exact combinational paths; do not blanket-disable asynchronous control timing.
- **ANALYSIS**: one-sided reset recovery remains functionally unsupported even if timing constraints are clean.

## Case Analysis And Multicycle Paths

- **ANALYSIS**: case analysis is allowed only for profile compile-time constants and static mode pins that are fixed by the elaborated configuration.
- **ANALYSIS**: no multicycle exception is proposed for AXI handshakes, admission, AW planning, CQ owner publication, or FIFO control.
- **TBD_MEASUREMENT**: add a multicycle path only after a cycle-level protocol proof and endpoint-specific timing report demonstrate the requirement.

## Prohibited Constraint Shortcuts

- **ANALYSIS**: no blanket false path between all clocks when it suppresses Gray timing.
- **ANALYSIS**: no false path through all RAM data pins.
- **ANALYSIS**: no clock uncertainty reduction solely to improve WNS.
- **ANALYSIS**: no unconstrained output or internal endpoint accepted as timing closure.
- **ANALYSIS**: no reuse of the old single-clock/full-wrapper assumption for Async512.

## Required Audits

1. **ANALYSIS**: clock object count and period assertion.
2. **ANALYSIS**: constrained/unconstrained endpoint inventory by clock and IO class.
3. **ANALYSIS**: exact Gray register and first-stage synchronizer count.
4. **ANALYSIS**: exception precedence and overridden-constraint report.
5. **ANALYSIS**: recovery/removal coverage.
6. **ANALYSIS**: mapped-netlist and SDC SHA-256 identity through DC, OpenROAD/OpenRCX, and PrimeTime.

