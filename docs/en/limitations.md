# Limitations

- This release freezes only the 512-bit SLVC profile; a 128-bit standard RTL
  profile is not implemented.
- The 200 MHz result is OOC, not a board implementation or lossless 10G claim.
- The selected simulation set is directed regression, not coverage or formal closure.
- ASIC libraries, SRAM macros, DFT, P&R, post-layout STA, and signoff are not complete.
- The exact release commit has not repeated U5 board validation.
- Carrier CDC has directed verification but no complete signoff and waiver package.
- The optional UDP/IPv4 adapter is a fixed receive profile, not a complete
  Ethernet/IP stack; it excludes VLAN, IPv6, options, fragments, UDP checksum,
  and FCS handling.
- Adapter-only DC OOC is not full-DMA ASIC synthesis, physical implementation,
  signoff, board-level 10G, or lossless UDP evidence.
- Optional RX memory development profiles are limited to same-clock 512,
  async64, and async512. They do not implement arbitrary 128/256-bit memory
  widths, unaligned first-beat shifting, TX/CQ widening, or multi-port striping.
- Async profiles require both hard resets to assert together. Arbitrary
  one-sided reset and recovery are unsupported. Soft reset blocks new RX,
  TX/descriptor, and UFC launches, drains already accepted work, and commits
  only after a memory-domain acknowledgement. Bounded completion assumes both
  clocks run and every downstream interface eventually responds; this is not a
  general external AXI reset protocol.
- The CDC evidence covers the implemented FIFO structures, simulation
  assertions, directional Vivado CDC reports, and bus skew. It is not a
  complete ASIC CDC/RDC signoff and waiver package.
- The routed async64 OOC result retains three `PDRC-190` synchronizer-placement
  warnings. Both asynchronous OOC profiles retain BRAM/reset DRC warnings from
  the integration top. These warnings are disclosed, not waived as signoff.
- RX backend Vivado results are OOC and Design Compiler results are frontend
  OOC synthesis with generic FIFO arrays. They are not full-system FPGA,
  board DDR, routed ASIC, SRAM-macro, physical-design, or signoff evidence.
