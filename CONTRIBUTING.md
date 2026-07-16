# Contributing

Issues and proposed patches are welcome when they can be reproduced using the
public profile and sources. Begin with the public tag or commit, selected top
module, host/tool version, exact command, expected behavior, actual behavior,
and a sanitized log excerpt.

The public repository is a generated delivery artifact. Maintainers review an
accepted public proposal in the private delivery source, regenerate provenance
and checksums from the approved allowlist, then publish the resulting export to
`main`. A public pull request may be used for discussion, but direct merges
must not bypass this delivery/export path.

Do not submit PDK files, Liberty/LEF/DB/GDS data, licenses, credentials,
private paths, generated FPGA IP, board projects, or proprietary tool logs.
Contributions must preserve the fixed 512-bit public profile unless a separately
reviewed profile and evidence package is introduced.
