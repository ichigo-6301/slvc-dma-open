from __future__ import print_function

import io
import unittest
from contextlib import redirect_stdout
from unittest import mock

from flows.scripts import validate_dma_async64_throughput as validator


class PublishedAsync64ThroughputValidatorTest(unittest.TestCase):
    def test_uses_base_owned_gate_without_recursive_validator_execution(self):
        with mock.patch.object(
                validator, "publication_validate",
                return_value=validator.PUBLISHED_STATUS) as validate:
            self.assertEqual(
                validator.validate("."), validator.PUBLISHED_STATUS
            )
        self.assertFalse(validate.call_args[1]["execute_validators"])

    def test_rejects_unpublished_state(self):
        with mock.patch.object(
                validator, "publication_validate",
                return_value="NOT_PUBLISHED"):
            with self.assertRaisesRegex(
                    validator.PublicationError, "not active"):
                validator.validate(".")

    def test_cli_reports_published_status(self):
        stream = io.StringIO()
        with mock.patch.object(
                validator, "validate",
                return_value=validator.PUBLISHED_STATUS), \
                redirect_stdout(stream):
            self.assertEqual(validator.main(["--root", "."]), 0)
        self.assertIn(validator.PUBLISHED_STATUS, stream.getvalue())


if __name__ == "__main__":
    unittest.main()
