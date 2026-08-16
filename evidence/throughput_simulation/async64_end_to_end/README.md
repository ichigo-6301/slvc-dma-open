# Async64 End-to-End RTL Simulation Throughput Evidence

Status: `VERIFIED_RTL_SIMULATION`. This package is a public RTL-simulation claim and is not resume eligible.

Profile: 16 RX/16 TX contexts, Async64 64-bit memory backend, `aclk=mem_clk=100 MHz` with 3 ns phase, seed 71.

Main point: 1024 x 4 KiB complete TX-to-RX loopback with the HP0_SHARED model, 16-cycle response latency, and 100% service.

| Window | MB/s/MHz | MB/s at 100 MHz | Gb/s at 100 MHz | Model efficiency |
| --- | ---: | ---: | ---: | ---: |
| Hardware end-to-end | 3.831177 | 383.117735 | 3.064942 | 95.779434% |
| Datapath steady-state | 3.831723 | 383.172335 | 3.065379 | 95.793084% |

Windows ModelSim SE-64 2020.4 and Linux Questa Sim-64 10.7c matched across the 28-point matrix. Peak outstanding reached 4, all 16 flows completed fairly, and drop, protocol error, and deadlock counts were zero.

FPGA emulation: **Pending / not measured / not claimed**.

The 4 MB/s/MHz HP0_SHARED value is a payload-only model ceiling. This result is not FPGA/HP0 board throughput, DDR peak, Fmax, the Same-clock512/Async512 64 B/cycle interface result, or ASIC evidence. C2B4 physical sources remained unchanged and no DC, P&R, OpenRCX, or PrimeTime rerun was performed.
