#!/usr/bin/env python3
"""Validate the published Async64 result through the base-owned gate."""

from __future__ import print_function

import argparse
from pathlib import Path

try:
    from flows.scripts.validate_throughput_publication_gate import (
        PublicationError,
        validate as publication_validate,
    )
except ImportError:
    from validate_throughput_publication_gate import (  # type: ignore
        PublicationError,
        validate as publication_validate,
    )


PUBLISHED_STATUS = "VERIFIED_RTL_SIMULATION_PUBLISHED"


def validate(root):
    status = publication_validate(
        Path(root).resolve(), execute_validators=False
    )
    if status != PUBLISHED_STATUS:
        raise PublicationError(
            "Async64 throughput publication is not active: {}".format(status)
        )
    return status


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=".")
    args = parser.parse_args(argv)
    try:
        status = validate(args.root)
    except PublicationError as error:
        print("async64-throughput-publication: FAIL: {}".format(error))
        return 1
    print("async64-throughput-publication: {}".format(status))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
