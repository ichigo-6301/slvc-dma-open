# Delivery Status

| Stage | Status | Public boundary |
| --- | --- | --- |
| Directed RTL regression | verified | Release-bound core/adapter, writer, async64/async512, and C2 focused suites passed on Windows ModelSim and IC_EDA Questa at their evidence-bound source commits. |
| Optional adapter regression | verified | Four adapter tests passed on both simulator hosts at the repaired source commit; the 23-case matrix is `cases=23 drops=17 accepts=23`. |
| FPGA OOC implementation | verified | Historical Vivado 2018.3 results remain frozen; a separate Vivado 2022.2 async64 run met 200 MHz routed OOC timing with 52 classified warnings. |
| Optional RX memory profiles | verified development | Same-clock 512, async64, and async512 passed profile regression and routed OOC; this does not change RC1. |
| Adapter ASIC frontend | verified | Adapter-only DC OOC met 5.000 ns; this is not full-DMA or signoff evidence. |
| Carrier CDC | partial | Directed behavior exists; no complete CDC/RDC signoff or waiver package. |
| C2B4 register ASIC | verified stage / partial profile | DC closed a 550 MHz mapped handoff; OpenROAD/OpenRCX/PT closed the internal 450 MHz nominal point with same-run hashes. This is a two-channel memory subsystem, not C4B4 or complete DMA. |
| SRAM A5 clock delivery | verified stage / blocked profile | The one-macro canary closed slew, route, extraction, setup, and hold; proxy minimum-pulse checks block C4B4 execution. |
| Foundry signoff STA | not claimed | No IO model, OCV/MMMC, signoff extraction, foundry-qualified SRAM, or silicon evidence is distributed. |
| Board validation | not claimed | The exact public release commit has no board-level claim. |
| Lossless 10G operation | not claimed | The release is not a completed board-level 10G production validation. |

The public repository does not publish PDK payloads, physical abstracts,
generated netlists, tool logs, licenses, or private paths. The C2 evidence
records same-run artifact hashes without distributing those payloads. SRAM A5
must complete independent pulse characterization before its physical profile
can advance.

The asynchronous RX memory rows have structural CDC reports and reset-contract
tests but remain outside a complete ASIC CDC/RDC signoff and waiver package.
