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
