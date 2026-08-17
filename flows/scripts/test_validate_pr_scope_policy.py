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

    def test_throughput_publication_exact_scope_passes(self):
        self.assertEqual(
            policy.validate_event(
                event(11, "3" * 40),
                policy.THROUGHPUT_REQUIRED_PATHS,
                BOOTSTRAP_HEAD,
            ),
            "THROUGHPUT_EVIDENCE_SCOPE_PASS",
        )

    def test_throughput_scope_matches_as_run_changed_sources(self):
        required = policy.THROUGHPUT_REQUIRED_PATHS
        for path in (
                "flows/scripts/validate_dma_async64_throughput_repaired.py",
                "flows/scripts/test_validate_dma_async64_throughput_repaired.py",
                "pattern/tb_rtl_rx_mem_async_backend.v"):
            self.assertIn(path, required)
        self.assertNotIn("rtl/integration/frame_dma_rx_top.v", required)

    def test_throughput_publication_requires_complete_contract(self):
        changed = set(policy.THROUGHPUT_REQUIRED_PATHS)
        changed.remove("pattern/tb_rtl_dma_axi_read_prefetch.v")
        with self.assertRaisesRegex(policy.PolicyError, "missing required path"):
            policy.validate_event(event(11, "3" * 40), changed, BOOTSTRAP_HEAD)

    def test_throughput_publication_cannot_modify_policy(self):
        changed = set(policy.THROUGHPUT_REQUIRED_PATHS)
        changed.add("Makefile")
        with self.assertRaisesRegex(policy.PolicyError, "must not modify trusted policy"):
            policy.validate_event(event(11, "3" * 40), changed, BOOTSTRAP_HEAD)

    def test_throughput_publication_cannot_replace_showcase_generator(self):
        for path in (
                "flows/scripts/generate_showcase_assets.py",
                "flows/scripts/test_generate_showcase_assets.py",
                "flows/scripts/check_showcase_render.py"):
            changed = set(policy.THROUGHPUT_REQUIRED_PATHS)
            changed.add(path)
            with self.subTest(path=path):
                with self.assertRaisesRegex(policy.PolicyError, "forbidden path"):
                    policy.validate_event(
                        event(11, "3" * 40), changed, BOOTSTRAP_HEAD
                    )

    def test_throughput_publication_rejects_protected_design_paths(self):
        forbidden = (
            "evidence/asic_paired_dc/points.csv",
            "flows/asic/c2b4/c2b4_register.f",
            "configs/slvc_dma_512_defconfig",
            "constraints/slvc_dma.xdc",
            "rtl/rx/dma_rx512_memory_subsystem_top.v",
        )
        for path in forbidden:
            changed = set(policy.THROUGHPUT_REQUIRED_PATHS)
            changed.add(path)
            with self.subTest(path=path):
                with self.assertRaises(policy.PolicyError):
                    policy.validate_event(event(11, "3" * 40), changed, BOOTSTRAP_HEAD)

    def test_asic_and_throughput_publication_cannot_be_mixed(self):
        changed = set(policy.THROUGHPUT_REQUIRED_PATHS)
        changed.add("evidence/asic_paired_dc/points.csv")
        with self.assertRaisesRegex(policy.PolicyError, "separate pull requests"):
            policy.validate_event(event(11, "3" * 40), changed, BOOTSTRAP_HEAD)

    def test_fpga_emulation_publication_exact_scope_passes(self):
        self.assertEqual(
            policy.validate_event(
                event(12, "3" * 40),
                policy.FPGA_EMULATION_REQUIRED_PATHS,
                BOOTSTRAP_HEAD,
            ),
            "FPGA_EMULATION_EVIDENCE_SCOPE_PASS",
        )

    def test_fpga_emulation_publication_requires_complete_contract(self):
        changed = set(policy.FPGA_EMULATION_REQUIRED_PATHS)
        changed.remove("fpga/u5/benchmark/helloworld.c")
        with self.assertRaisesRegex(policy.PolicyError, "missing required path"):
            policy.validate_event(event(12, "3" * 40), changed, BOOTSTRAP_HEAD)

    def test_fpga_emulation_publication_requires_debugger_transcript(self):
        changed = set(policy.FPGA_EMULATION_REQUIRED_PATHS)
        changed.remove(
            "evidence/fpga_emulation/u5_sync_hp0_loopback/"
            "debugger_capture_transcript.txt"
        )
        with self.assertRaisesRegex(policy.PolicyError, "missing required path"):
            policy.validate_event(event(12, "3" * 40), changed, BOOTSTRAP_HEAD)

    def test_fpga_emulation_publication_rejects_rtl_and_policy(self):
        for path in ("rtl/tx/dma_axi_read_prefetch.v", "Makefile"):
            changed = set(policy.FPGA_EMULATION_REQUIRED_PATHS)
            changed.add(path)
            with self.subTest(path=path):
                with self.assertRaises(policy.PolicyError):
                    policy.validate_event(
                        event(12, "3" * 40), changed, BOOTSTRAP_HEAD
                    )

    def test_fpga_and_rtl_simulation_publications_cannot_be_mixed(self):
        changed = set(policy.FPGA_EMULATION_REQUIRED_PATHS)
        changed.add("evidence/throughput_simulation/async64_end_to_end/manifest.json")
        with self.assertRaisesRegex(policy.PolicyError, "separate pull requests"):
            policy.validate_event(event(12, "3" * 40), changed, BOOTSTRAP_HEAD)

    def test_published_fpga_evidence_cannot_be_modified_or_removed(self):
        with self.assertRaisesRegex(policy.PolicyError, "already-published"):
            policy.validate_event(
                event(12, "3" * 40),
                policy.FPGA_EMULATION_REQUIRED_PATHS,
                BOOTSTRAP_HEAD,
                base_fpga_claim_registered=True,
            )

    def test_fpga_bram_publication_exact_scope_passes(self):
        self.assertEqual(
            policy.validate_event(
                event(17, "3" * 40),
                policy.FPGA_BRAM_REQUIRED_PATHS,
                BOOTSTRAP_HEAD,
            ),
            "FPGA_BRAM_EVIDENCE_SCOPE_PASS",
        )

    def test_fpga_bram_publication_requires_complete_contract(self):
        changed = set(policy.FPGA_BRAM_REQUIRED_PATHS)
        changed.remove(
            "evidence/fpga_resources/u5_13ch_bram_architecture/resources.csv"
        )
        with self.assertRaisesRegex(policy.PolicyError, "missing required path"):
            policy.validate_event(event(17, "3" * 40), changed, BOOTSTRAP_HEAD)

    def test_fpga_bram_publication_rejects_rtl_and_policy(self):
        for path in (
                "rtl/rx/dma_frame_shared_pool.v",
                "flows/scripts/validate_fpga_bram_architecture_evidence.py"):
            changed = set(policy.FPGA_BRAM_REQUIRED_PATHS)
            changed.add(path)
            with self.subTest(path=path):
                with self.assertRaises(policy.PolicyError):
                    policy.validate_event(
                        event(17, "3" * 40), changed, BOOTSTRAP_HEAD
                    )

    def test_fpga_bram_and_board_throughput_cannot_be_mixed(self):
        changed = set(policy.FPGA_BRAM_REQUIRED_PATHS)
        changed.add(
            "evidence/fpga_emulation/u5_sync_hp0_loopback/manifest.json"
        )
        with self.assertRaisesRegex(policy.PolicyError, "separate pull requests"):
            policy.validate_event(event(17, "3" * 40), changed, BOOTSTRAP_HEAD)

    def test_published_fpga_bram_evidence_cannot_be_modified_or_removed(self):
        with self.assertRaisesRegex(policy.PolicyError, "already-published"):
            policy.validate_event(
                event(17, "3" * 40),
                policy.FPGA_BRAM_REQUIRED_PATHS,
                BOOTSTRAP_HEAD,
                base_fpga_bram_claim_registered=True,
            )

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
