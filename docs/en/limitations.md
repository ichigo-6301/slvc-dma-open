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
- The optional 512-bit RX payload master is a same-clock, 64-byte-aligned
  development profile. It has no AXI CDC, unaligned first-beat support, TX/CQ
  widening, or board DDR bandwidth measurement.
- Its Vivado result is OOC and its Design Compiler result is writer-only
  frontend synthesis. Neither is full-system FPGA implementation, routed ASIC
  timing, physical design, or signoff evidence.
- The RX-wide profile retains destructive synchronous soft-reset semantics and
  does not claim safe draining of already-issued external AXI bursts.
