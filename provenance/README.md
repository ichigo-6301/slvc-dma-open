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
