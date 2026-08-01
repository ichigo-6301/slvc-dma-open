# Public Provenance

The `source_commit` and `delivery_commit` fields are immutable identifiers from
the private engineering repository. They are retained for internal traceability
but are not resolvable from this public repository.

Public consumers should verify `v0.1.0-rc1` in
`https://github.com/ichigo-6301/slvc-dma-open` together with
`provenance/checksums.sha256`. The release tag was refreshed after its initial
publication to repair Python 3.6 and Linux Questa portability; the initial tag
object was `31d2d0a86e3ea0d8dfefb01d4753980ea98d1a83` and peeled to
`ce283357974ff3678bfcdf8d51ce8523166d097c`.

The optional UDP/IPv4 adapter P0 is exported as a commit-bound preview profile,
not as a moved or replacement RC1 tag. Its generated `release.yaml` binds the
adapter source and delivery commits, while inherited core evidence retains its
original fixed source references.

Optional RX payload memory backends are branch-local development profiles.
[`rx_payload_cdc_development.yaml`](rx_payload_cdc_development.yaml) binds
their implementation commit and four evidence summaries without changing
`release.yaml`, public `main`, or the frozen RC1 tag.

Current `main` exposes implementation stages through GNU Make. Python remains
an internal fail-closed dispatcher for configuration, native log markers, and
artifact audits. [`make_flow_interface.yaml`](make_flow_interface.yaml) records
that interface-only migration separately from measured RTL, FPGA, and ASIC
evidence.

[`asic_paired_dc_publication.yaml`](asic_paired_dc_publication.yaml) binds the
sanitized Writer component, C2B4 Writer-subsystem, and Shared Pool paired-DC
tables to fixed evidence commits and public file SHA-256 values. The public
package contains normalized CSV/JSON-syntax YAML and artifact hashes, not raw
commercial reports, logs, netlists, DDC, SDC, host, account, or license
configuration. Its three claim IDs are scope-distinct and cannot be promoted
across component, subsystem, or complete-DMA boundaries. `points.csv` is the
only numeric authority; `comparisons.csv` is regenerated with `Decimal`, six
fractional digits, and `ROUND_HALF_EVEN`.

Replacing fixed points, hidden-report digests, or registry records uses two
reviewed changes: first update the base-owned validator constants in a policy
PR, then publish the matching payload in an evidence-only PR. The comparison
writer regenerates derivatives and digest chains only after the trusted point
identity has been accepted; it is not an authorization to replace evidence.
