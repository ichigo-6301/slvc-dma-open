# Delivery Status

| Stage | Status | Public boundary |
| --- | --- | --- |
| Directed RTL regression | verified | Ten release-bound tests passed on Windows ModelSim and IC_EDA Questa. |
| FPGA OOC implementation | verified | Three Vivado 2018.3 strategies met 200 MHz OOC setup and hold. |
| Carrier CDC | partial | Directed behavior exists; no complete CDC/RDC signoff or waiver package. |
| ASIC frontend | planned | A future library-bound synthesis profile requires its own evidence. |
| Physical implementation | blocked | Validated standard-cell and SRAM macro physical views are not yet available for a reproducible handoff. |
| Signoff STA | planned | Requires a routed netlist, constraints, parasitics, and matching libraries. |
| Board validation | not claimed | The exact public release commit has no board-level claim. |
| Lossless 10G operation | not claimed | The release is not a completed board-level 10G production validation. |

The physical blocker is intentionally generic. The repository does not publish
PDK payloads, physical abstracts, tool logs, licenses, paths, or proprietary
integration details. Recovery requires a separate prerequisite audit and new
profile-bound evidence.
