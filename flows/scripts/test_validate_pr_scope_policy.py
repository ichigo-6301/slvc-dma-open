#!/usr/bin/env python3
"""Unit tests for the base-owned pull-request scope policy."""

import unittest

from flows.scripts import validate_pr_scope_policy as policy


BOOTSTRAP_HEAD = "2" * 40


def event(number, head=BOOTSTRAP_HEAD):
    return {
        "number": number,
        "repository": {"full_name": policy.REPOSITORY},
        "pull_request": {
            "base": {"ref": "main", "sha": "1" * 40},
            "head": {"sha": head},
        },
    }


class TrustedScopePolicyTest(unittest.TestCase):
    def test_bootstrap_exact_identity_and_paths_pass(self):
        self.assertEqual(
            policy.validate_event(event(2), policy.BOOTSTRAP_PATHS, BOOTSTRAP_HEAD),
            "BOOTSTRAP_EVIDENCE_SCOPE_PASS",
        )

    def test_bootstrap_head_drift_fails(self):
        with self.assertRaisesRegex(policy.PolicyError, "head SHA mismatch"):
            policy.validate_event(event(2, "3" * 40), policy.BOOTSTRAP_PATHS, BOOTSTRAP_HEAD)

    def test_bootstrap_path_drift_fails(self):
        with self.assertRaisesRegex(policy.PolicyError, "exact path set mismatch"):
            policy.validate_event(
                event(2), set(policy.BOOTSTRAP_PATHS) | {"rtl/x.v"}, BOOTSTRAP_HEAD
            )

    def test_bootstrap_requires_admin_configured_head(self):
        with self.assertRaisesRegex(policy.PolicyError, "not configured"):
            policy.validate_event(event(2), policy.BOOTSTRAP_PATHS, "")

    def test_future_publication_only_passes(self):
        changed = {
            "evidence/asic_paired_dc/points.csv",
            "provenance/checksums.sha256",
        }
        self.assertEqual(
            policy.validate_event(event(9, "3" * 40), changed, BOOTSTRAP_HEAD),
            "EVIDENCE_SCOPE_PASS",
        )

    def test_future_evidence_cannot_modify_policy(self):
        changed = {
            "evidence/asic_paired_dc/points.csv",
            "flows/scripts/validate_pr_scope_policy.py",
        }
        with self.assertRaisesRegex(policy.PolicyError, "must not modify trusted policy"):
            policy.validate_event(event(9, "3" * 40), changed, BOOTSTRAP_HEAD)

    def test_future_evidence_cannot_modify_rtl(self):
        changed = {"evidence/asic_paired_dc/points.csv", "rtl/dma.v"}
        with self.assertRaisesRegex(policy.PolicyError, "forbidden path"):
            policy.validate_event(event(9, "3" * 40), changed, BOOTSTRAP_HEAD)

    def test_metadata_and_policy_combination_fails(self):
        changed = {
            "provenance/evidence.yaml",
            "flows/scripts/validate_pr_scope_policy.py",
        }
        with self.assertRaisesRegex(policy.PolicyError, "must not modify trusted policy"):
            policy.validate_event(event(9, "3" * 40), changed, BOOTSTRAP_HEAD)

    def test_unrelated_pr_is_not_applicable(self):
        self.assertEqual(
            policy.validate_event(event(9, "3" * 40), {"README.md"}, BOOTSTRAP_HEAD),
            "NOT_APPLICABLE",
        )

    def test_global_checksum_does_not_activate_evidence_scope(self):
        self.assertEqual(
            policy.validate_event(
                event(9, "3" * 40),
                {"README.md", "provenance/checksums.sha256"},
                BOOTSTRAP_HEAD,
            ),
            "NOT_APPLICABLE",
        )

    def test_renamed_policy_source_path_is_rejected(self):
        changed = {
            ".github/workflows/trusted-evidence-scope.yml",
            "evidence/asic_paired_dc/README.md",
            "provenance/checksums.sha256",
        }
        with self.assertRaisesRegex(policy.PolicyError, "must not modify trusted policy"):
            policy.validate_event(event(9, "3" * 40), changed, BOOTSTRAP_HEAD)

    def test_repository_and_base_are_fixed(self):
        wrong_repo = event(9, "3" * 40)
        wrong_repo["repository"]["full_name"] = "other/repo"
        with self.assertRaisesRegex(policy.PolicyError, "repository identity"):
            policy.validate_event(wrong_repo, {"README.md"}, BOOTSTRAP_HEAD)
        wrong_base = event(9, "3" * 40)
        wrong_base["pull_request"]["base"]["ref"] = "develop"
        with self.assertRaisesRegex(policy.PolicyError, "base branch"):
            policy.validate_event(wrong_base, {"README.md"}, BOOTSTRAP_HEAD)


if __name__ == "__main__":
    unittest.main()
