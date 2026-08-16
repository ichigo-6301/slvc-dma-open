#!/usr/bin/env python3
"""Mutation tests for the Async64 publication gate."""

import json
import re
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from flows.scripts import generate_showcase_assets as showcase_generator
from flows.scripts import validate_throughput_publication_gate as gate


ROOT = Path(__file__).resolve().parents[2]
SOURCE_REF = gate.TRUSTED_FLOW_AS_RUN_COMMIT
REVIEWED_SOURCE_REF = "c82118cfbf28633d82a315925a390143c91ea117"
REVIEWED_ARTIFACTS_SHA256 = (
    "4d010378812ee203584f42066930349684c9e0e13c2a9c650abf21d0775cded5"
)
REVIEWED_C2B4_IDENTITY_SHA256 = (
    "da7473a1879c61c68ec38832fd30b523146dc25920cdff8d89e0c8f93a970d3c"
)


def _yaml_record(item_id, fields):
    lines = ["  - id: {}".format(item_id)]
    for key, value in fields:
        if isinstance(value, list):
            lines.append("    {}:".format(key))
            lines.extend("      - {}".format(json.dumps(item)) for item in value)
        else:
            lines.append("    {}: {}".format(key, json.dumps(value)))
    return "\n".join(lines) + "\n"


CLAIM_BLOCK = _yaml_record(gate.CLAIM_ID, [
    ("profile", gate.CLAIM_FIXED["profile"]),
    ("statement", gate.CLAIM_FIXED["statement"]),
    ("metric", gate.CLAIM_FIXED["metric"]),
    ("value", gate.CLAIM_FIXED["value"]),
    ("unit", gate.CLAIM_FIXED["unit"]),
    ("benchmark", gate.CLAIM_FIXED["benchmark"]),
    ("configuration", gate.CLAIM_FIXED["configuration"]),
    ("source_ref", SOURCE_REF),
    ("tool", gate.CLAIM_FIXED["tool"]),
    ("evidence", gate.CLAIM_FIXED["evidence"]),
    ("status", gate.CLAIM_FIXED["status"]),
    ("caveat", gate.CLAIM_FIXED["caveat"]),
    ("resume_eligible", gate.CLAIM_FIXED["resume_eligible"]),
    ("public", gate.CLAIM_FIXED["public"]),
])

NONCLAIM_BLOCK = _yaml_record(
    gate.NONCLAIM_ID, list(gate.NONCLAIM_FIXED.items())
)


def _without_registry_item(text, item_id):
    pattern = re.compile(
        r"(?ms)^  - id: " + re.escape(item_id) + r"\n.*?(?=^  - id: |\Z)"
    )
    matches = list(pattern.finditer(text))
    if len(matches) > 1:
        raise AssertionError("duplicate fixture registry item: {}".format(item_id))
    if not matches:
        return text
    match = matches[0]
    return text[:match.start()] + text[match.end():]


def _without_bounded_block(text, start, end):
    pattern = re.compile(
        r"(?ms)^" + re.escape(start) + r"\n.*?^" + re.escape(end) + r"\n?"
    )
    matches = list(pattern.finditer(text))
    if len(matches) > 1:
        raise AssertionError("duplicate fixture publication block")
    if not matches:
        return text
    match = matches[0]
    return text[:match.start()] + text[match.end():]


class ThroughputPublicationGateTest(unittest.TestCase):
    unpublished_source_blobs = {}

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def _copy_provenance(self, published_sources=False):
        self.source_blobs = {}
        for relative in (gate.CLAIMS_REL, gate.EVIDENCE_REL, gate.NONCLAIMS_REL,
                         gate.SHOWCASE_REL):
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / relative, target)
        for relative, item_id in (
                (gate.CLAIMS_REL, gate.CLAIM_ID),
                (gate.EVIDENCE_REL, gate.EVIDENCE_ID),
                (gate.NONCLAIMS_REL, gate.NONCLAIM_ID)):
            path = self.root / relative
            path.write_text(
                _without_registry_item(
                    path.read_text(encoding="utf-8"), item_id
                ),
                encoding="utf-8",
            )
        for relative in (
                Path("README.md"), Path("README.en.md"),
                Path("docs/en/results.md"), Path("docs/zh-CN/results.md")):
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / relative, target)
            if relative.name.startswith("README"):
                start, end = gate.README_START, gate.README_END
            else:
                start, end = gate.RESULTS_START, gate.RESULTS_END
            target.write_text(
                _without_bounded_block(
                    target.read_text(encoding="utf-8"), start, end
                ),
                encoding="utf-8",
            )

        manifest = json.loads(
            (ROOT / gate.SHOWCASE_REL).read_text(encoding="utf-8")
        )
        manifest["assets"] = [
            asset for asset in manifest["assets"]
            if asset.get("path") != gate.CHART_REL.as_posix()
        ]
        (self.root / gate.SHOWCASE_REL).write_text(
            json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
        )
        copy_paths = set()
        for asset in manifest["assets"]:
            copy_paths.add(Path(asset["path"]))
            if "generator" in asset:
                copy_paths.add(Path(asset["generator"]))
            for source in asset.get("inputs", []):
                copy_paths.add(Path(source["path"]))
        for relative in copy_paths:
            target = self.root / relative
            if target.exists():
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / relative, target)
        for relative in gate.REQUIRED_SOURCE_PATHS:
            target = self.root / relative
            if (not published_sources and
                    relative in gate.UNPUBLISHED_ABSENT_SOURCE_PATHS):
                if target.is_file():
                    target.unlink()
                continue
            if published_sources:
                source = ROOT / relative
                if not source.is_file():
                    continue
                data = source.read_bytes()
            else:
                data = self.unpublished_source_blobs.get(relative)
                if data is None:
                    data = gate._source_blob(
                        ROOT, gate.UNPUBLISHED_SOURCE_REF, relative
                    )
                    self.unpublished_source_blobs[relative] = data
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            self.source_blobs[relative] = data
        manifest_path = self.root / gate.SHOWCASE_REL
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        for asset in manifest["assets"]:
            for source in asset.get("inputs", []):
                source["sha256"] = gate._sha256(
                    (self.root / source["path"]).read_bytes()
                )
        manifest_path.write_text(
            json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
        )

    @staticmethod
    def _append(path, text):
        with path.open("a", encoding="utf-8", newline="\n") as handle:
            handle.write(text)

    @staticmethod
    def _insert_before(path, follower, text):
        content = path.read_text(encoding="utf-8")
        if content.count(follower) != 1:
            raise AssertionError("fixture follower mismatch: {}".format(path))
        path.write_text(
            content.replace(follower, text + follower, 1),
            encoding="utf-8",
        )

    def _published_fixture(self):
        self._copy_provenance(published_sources=True)
        for relative in gate.REQUIRED_PATHS:
            target = self.root / relative
            if not target.exists():
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text("fixture\n", encoding="utf-8")
        for relative_text in gate.REQUIRED_SOURCE_PATHS:
            relative = Path(relative_text)
            target = self.root / relative
            if target.exists():
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            source = ROOT / relative
            if source.is_file():
                shutil.copyfile(source, target)
            else:
                target.write_text("fixture source\n", encoding="utf-8")
        summary = {
            "schema": "slvc_dma_async64_end_to_end_rtl_simulation_v1",
            "classification": "VERIFIED_RTL_SIMULATION",
            "claim_id": gate.CLAIM_ID,
            "numeric_authority": (gate.PACKAGE_REL / "points.csv").as_posix(),
            "source_ref": SOURCE_REF,
            "profile": gate.SUMMARY_PROFILE,
            "main_point": gate.SUMMARY_MAIN_POINT,
            "validation": gate.SUMMARY_VALIDATION,
            "boundaries": gate.SUMMARY_BOUNDARIES,
            "fpga_emulation": {
                "status": "pending_not_measured_not_claimed", "value": None,
            },
        }
        summary_path = self.root / gate.SUMMARY_REL
        summary_path.write_text(
            json.dumps(summary, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        package_readme = self.root / gate.PACKAGE_REL / "README.md"
        package_readme.write_text(
            gate.EXPECTED_PACKAGE_README,
            encoding="utf-8",
        )
        package_files = {
            path.name for path in gate.REQUIRED_PATHS
            if path.parent == gate.PACKAGE_REL and path.name != "manifest.json"
        }
        source_records = []
        self.source_blobs = {}
        for relative in gate.REQUIRED_SOURCE_PATHS:
            data = (self.root / relative).read_bytes()
            self.source_blobs[relative] = data
            source_records.append({
                "path": relative,
                "sha256": gate._sha256(data),
                "size_bytes": len(data),
            })
        package_manifest = {
            "schema_version": 3,
            "experiment_id": "slvc_dma_async64_end_to_end_rtl_simulation",
            "classification": "VERIFIED_RTL_SIMULATION",
            "flow_as_run_commit": SOURCE_REF,
            "claim_id": gate.CLAIM_ID,
            "public_claim_eligible": True,
            "resume_eligible": False,
            "formal_matrix_completed": True,
            "correctness_ladder_completed": True,
            "dual_platform_complete": True,
            "c2b4_physical_source_changed": False,
            "c2b4_physical_rerun_performed": False,
            "rtl_fix_commit": gate.TRUSTED_RTL_FIX_COMMIT,
            "baseline_commit": "c20681fad0eaa6ad55dbb919149765b175b29117",
            "blocked_evidence_commit": "e6a6696603b10c4475fca468e9c40c727197ac9c",
            "profile": dict(
                gate.SUMMARY_PROFILE,
                descriptor_workload_entries=1024,
                descriptor_ring_capacity_entries=2048,
                cq_entries=4096,
            ),
            "main_point": dict(
                gate.SUMMARY_MAIN_POINT,
                workload="1024 x 4096-byte full TX-to-RX loopback",
            ),
            "boundaries": {
                "hp0_shared_is_board_measurement": False,
                "score_is_fmax": False,
                "sameclock512_64_bytes_per_cycle_claim_reused": False,
                "legacy_9p5_gbps_used_in_comparison": False,
                "public_claim_updated": True,
                "fpga_emulation_measured": False,
            },
            "document_sha256": gate._sha256(package_readme.read_bytes()),
            "files": {
                name: gate._sha256(
                    (self.root / gate.PACKAGE_REL / name).read_bytes()
                ) for name in package_files
            },
            "sources": source_records,
        }
        (self.root / gate.PACKAGE_REL / "manifest.json").write_text(
            json.dumps(package_manifest, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        evidence_block = _yaml_record(gate.EVIDENCE_ID, [
            ("path", gate.SUMMARY_REL.as_posix()),
            ("type", "bounded_dual_platform_rtl_simulation"),
            ("source_ref", SOURCE_REF),
            ("tool", gate.CLAIM_FIXED["tool"]),
            ("claims", [gate.CLAIM_ID]),
            ("sha256", gate._sha256(summary_path.read_bytes())),
            ("public", True),
        ])
        self._append(self.root / gate.CLAIMS_REL, CLAIM_BLOCK)
        self._append(self.root / gate.EVIDENCE_REL, evidence_block)
        self._append(self.root / gate.NONCLAIMS_REL, NONCLAIM_BLOCK)

        readme_blocks = {
            Path("README.md"): (
                gate.README_START + "\n" +
                "<!-- claim:{} maturity:verified -->\n".format(gate.CLAIM_ID) +
                "双平台 RTL 仿真：3.831177 MB/s/MHz；383.117735 MB/s；3.064942 Gb/s；"
                "95.779434%。详见[结果](docs/zh-CN/results.md)。\n" +
                gate.README_END + "\n"
            ),
            Path("README.en.md"): (
                gate.README_START + "\n" +
                "<!-- claim:{} maturity:verified -->\n".format(gate.CLAIM_ID) +
                "Dual-platform RTL simulation: 3.831177 MB/s/MHz; "
                "383.117735 MB/s; 3.064942 Gb/s; "
                "95.779434%. See [Results](docs/en/results.md).\n" +
                gate.README_END + "\n"
            ),
        }
        for relative, readme_block in readme_blocks.items():
            self._insert_before(
                self.root / relative,
                gate.README_BLOCK_FOLLOWER[relative],
                readme_block,
            )

        result_block = (
            gate.RESULTS_START + "\n" +
            "<!-- claim:{} maturity:verified -->\n".format(gate.CLAIM_ID) +
            '<p align="center"><a href="{asset}"><img src="{asset}" '
            'width="1000" alt="Async64 throughput"></a></p>\n'
            "3.831177 MB/s/MHz; 383.117735 MB/s; 3.064942 Gb/s; "
            "95.779434%. Pending / not measured / not claimed.\n" +
            gate.RESULTS_END + "\n"
        ).format(asset=gate.RESULTS_ASSET_LINK)
        for relative in (Path("docs/en/results.md"),
                         Path("docs/zh-CN/results.md")):
            self._append(self.root / relative, result_block)

        (self.root / gate.CHART_REL).write_text(
            '<svg xmlns="http://www.w3.org/2000/svg" width="1600" '
            'height="1000" viewBox="0 0 1600 1000" '
            'preserveAspectRatio="xMidYMid meet" data-claim-id="' +
            gate.CLAIM_ID + '" data-classification="VERIFIED_RTL_SIMULATION" '
            'data-e2e-mbps-per-mhz="3.831177" '
            'data-steady-mbps-per-mhz="3.831723" '
            'data-model-efficiency-percent="95.779434" '
            'data-fpga-emulation="pending-not-measured-not-claimed"><text>' +
            gate.CLAIM_ID + '</text><text>' +
            'Async64 End-to-End RTL Simulation Throughput | '
            '3.831177 MB/s/MHz | 3.831723 MB/s/MHz | 383.117735 MB/s | '
            '3.064942 Gb/s | 4.000000 MB/s/MHz | 95.779434% | '
            '64 B: 0.453734 MB/s/MHz | 128 B: 0.858762 MB/s/MHz | '
            '256 B: 1.514215 MB/s/MHz | 1024 B: 3.400603 MB/s/MHz | '
            '4096 B: 3.831177 MB/s/MHz | 50%: 1.941126 MB/s/MHz | '
            '75%: 2.892408 MB/s/MHz | 100%: 3.831177 MB/s/MHz | '
            'ModelSim SE-64 2020.4 + Questa Sim-64 10.7c | '
            'Peak outstanding = 4 | 16-flow fairness = PASS | '
            'Drop / protocol error / deadlock = 0 | '
            'Pending / not measured / not claimed | '
            'not FPGA/HP0 board throughput | not DDR peak | not Fmax | '
            'not ASIC evidence</text></svg>\n',
            encoding="utf-8",
        )
        manifest_path = self.root / gate.SHOWCASE_REL
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        generator = self.root / "flows/scripts/generate_showcase_assets.py"
        for asset in manifest["assets"]:
            if "generator_sha256" in asset:
                asset["generator_sha256"] = gate._sha256(generator.read_bytes())
            for source in asset.get("inputs", []):
                source["sha256"] = gate._sha256(
                    (self.root / source["path"]).read_bytes()
                )
        manifest["assets"].append({
            "path": gate.CHART_REL.as_posix(),
            "sha256": gate._sha256((self.root / gate.CHART_REL).read_bytes()),
            "format": "svg",
            "source": "bounded Async64 RTL simulation evidence",
            "source_type": "deterministic_generated_showcase",
            "numeric_authority": False,
            "generator": "flows/scripts/generate_showcase_assets.py",
            "generator_sha256": gate._sha256(generator.read_bytes()),
            "command": "python flows/scripts/generate_showcase_assets.py --root . --write",
            "claim_ids": [gate.CLAIM_ID],
            "inputs": [
                {"path": relative.as_posix(),
                 "sha256": gate._sha256((self.root / relative).read_bytes())}
                for relative in (
                    gate.SUMMARY_REL,
                    gate.PACKAGE_REL / "points.csv",
                    gate.CLAIMS_REL,
                )
            ],
        })
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

        self.trusted_evidence_hashes = {
            name: gate._sha256((self.root / gate.PACKAGE_REL / name).read_bytes())
            for name in gate.TRUSTED_EVIDENCE_FILE_SHA256
        }
        self.trusted_blocked_hashes = {
            name: gate._sha256(
                (self.root / gate.BLOCKED_PACKAGE_REL / name).read_bytes()
            ) for name in gate.TRUSTED_BLOCKED_FILE_SHA256
        }

    def _validate(self, execute_validators=False):
        trusted = getattr(
            self, "trusted_evidence_hashes", gate.TRUSTED_EVIDENCE_FILE_SHA256
        )
        blocked = getattr(
            self, "trusted_blocked_hashes", gate.TRUSTED_BLOCKED_FILE_SHA256
        )
        with mock.patch.object(gate, "TRUSTED_EVIDENCE_FILE_SHA256", trusted), \
                mock.patch.object(gate, "TRUSTED_BLOCKED_FILE_SHA256", blocked), \
                mock.patch.object(
                    gate, "_source_blob",
                    side_effect=lambda root, commit, relative:
                    self.source_blobs.get(relative)
                    if hasattr(self, "source_blobs") and
                    relative in self.source_blobs
                    else (Path(root) / relative).read_bytes(),
                ):
            return gate.validate(
                self.root, execute_validators=execute_validators
            )

    def _replace_points_with_showcase_fixture(self):
        header = (
            "platform,point_id,frames,payload_bytes,shared_service,"
            "response_latency_cycles,service_percent,mem_phase_ns,clock_mhz,"
            "hw_cycles,steady_cycles,rx_peak_outstanding,"
            "tx_peak_outstanding,frame_drop,deadlock,protocol_error,status"
        )
        identities = (
            ("loopback_peak_phase3", 4194304, 1094782, 1094626, 100, 4),
            ("loopback_size_64", 65536, 144437, 144274, 100, 1),
            ("loopback_size_128", 131072, 152629, 152474, 100, 1),
            ("loopback_size_256", 262144, 173122, 172966, 100, 2),
            ("loopback_size_1024", 1048576, 308350, 308194, 100, 4),
            ("loopback_size_4096", 4194304, 1094782, 1094626, 100, 4),
            ("hp0_l16_s50", 4194304, 2160758, 2160497, 50, 4),
            ("hp0_l16_s75", 4194304, 1450108, 1449900, 75, 4),
            ("hp0_l16_s100", 4194304, 1094782, 1094626, 100, 4),
        )
        rows = [header]
        for platform in ("windows", "linux"):
            for point_id, payload, hw_cycles, steady_cycles, service, peak in identities:
                rows.append(
                    "{},{},1024,{},1,16,{},3,100,{},{},{},{},0,0,0,PASS".format(
                        platform, point_id, payload, service, hw_cycles,
                        steady_cycles, peak, peak,
                    )
                )
        points_path = self.root / gate.PACKAGE_REL / "points.csv"
        points_path.write_text("\n".join(rows) + "\n", encoding="utf-8")

        manifest_path = self.root / gate.PACKAGE_REL / "manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["files"]["points.csv"] = gate._sha256(
            points_path.read_bytes()
        )
        manifest_path.write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        self.trusted_evidence_hashes["points.csv"] = gate._sha256(
            points_path.read_bytes()
        )

    def test_unpublished_tree_returns_explicit_status(self):
        self._copy_provenance()
        self.assertEqual(self._validate(),
                         "NOT_PUBLISHED")

    def test_unpublished_tree_still_protects_homepages(self):
        self._copy_provenance()
        path = self.root / "README.en.md"
        path.write_text(
            path.read_text(encoding="utf-8").replace(
                "# SLVC DMA\n",
                "# Rewritten homepage\n",
                1,
            ),
            encoding="utf-8",
        )
        with self.assertRaisesRegex(
                gate.PublicationError, "modifies protected homepage content"):
            self._validate()

    def test_unpublished_tree_rejects_source_and_harness_drift(self):
        for relative in (
                "rtl/rx/dma_rx_payload_cdc_bridge.v",
                "pattern/tb_rtl_rx_payload_cdc_bridge.v"):
            with self.subTest(path=relative):
                self._copy_provenance()
                path = self.root / relative
                path.write_text(
                    path.read_text(encoding="utf-8") +
                    "\n// unauthorized rollback mutation\n",
                    encoding="utf-8",
                )
                with self.assertRaisesRegex(
                        gate.PublicationError,
                        "protected pre-publication source changed"):
                    self._validate()
                shutil.rmtree(self.root)
                self.root.mkdir()

    def test_unpublished_tree_rejects_publication_only_source_residue(self):
        self._copy_provenance()
        relative = next(iter(sorted(gate.UNPUBLISHED_ABSENT_SOURCE_PATHS)))
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("residual publication source\n", encoding="utf-8")
        with self.assertRaisesRegex(
                gate.PublicationError, "publication-only source exists"):
            self._validate()

    def test_unpublished_tree_protects_remaining_public_contracts(self):
        mutations = (
            (gate.CLAIMS_REL, "\n# unauthorized registry rewrite\n"),
            (Path("docs/en/results.md"), "\nUnsupported result\n"),
            (gate.SHOWCASE_REL, "\n"),
        )
        for relative, suffix in mutations:
            with self.subTest(path=relative):
                self._copy_provenance()
                path = self.root / relative
                if relative == gate.SHOWCASE_REL:
                    manifest = json.loads(path.read_text(encoding="utf-8"))
                    manifest["assets"][0]["source"] = "rewritten source"
                    path.write_text(
                        json.dumps(manifest, indent=2) + "\n",
                        encoding="utf-8",
                    )
                else:
                    path.write_text(
                        path.read_text(encoding="utf-8") + suffix,
                        encoding="utf-8",
                    )
                with self.assertRaises(gate.PublicationError):
                    self._validate()
                shutil.rmtree(self.root)
                self.root.mkdir()

    def test_complete_publication_contract_passes(self):
        self._published_fixture()
        self.assertEqual(
            self._validate(),
            "VERIFIED_RTL_SIMULATION_PUBLISHED",
        )

    def test_reviewed_rerun_identity_is_fixed(self):
        self.assertEqual(gate.TRUSTED_FLOW_AS_RUN_COMMIT,
                         REVIEWED_SOURCE_REF)
        self.assertEqual(
            gate.TRUSTED_EVIDENCE_FILE_SHA256["artifacts.csv"],
            REVIEWED_ARTIFACTS_SHA256,
        )
        self.assertEqual(
            gate.TRUSTED_EVIDENCE_FILE_SHA256[
                "c2b4_physical_identity.json"
            ],
            REVIEWED_C2B4_IDENTITY_SHA256,
        )

    def test_complete_publication_contract_matches_showcase_generator(self):
        self._published_fixture()
        self._replace_points_with_showcase_fixture()
        for relative in (
                showcase_generator.ARCHITECTURE_PATH,
                showcase_generator.ARCHITECTURE_EN_PATH,
                showcase_generator.RESEARCH_PATH,
                showcase_generator.RESEARCH_EN_PATH):
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / relative, target)
        showcase_generator.write(self.root)
        showcase_generator.check(self.root)
        self.assertEqual(
            self._validate(),
            "VERIFIED_RTL_SIMULATION_PUBLISHED",
        )

    def test_publication_files_without_claim_fail(self):
        self._copy_provenance()
        target = self.root / gate.SUMMARY_REL
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text("{}\n", encoding="utf-8")
        with self.assertRaisesRegex(gate.PublicationError, "without the registered claim"):
            self._validate()

    def test_every_publication_file_is_a_no_claim_sentinel(self):
        self._copy_provenance()
        for relative in gate.PUBLICATION_SENTINELS:
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("residual publication artifact\n", encoding="utf-8")
            with self.subTest(path=relative):
                with self.assertRaisesRegex(
                        gate.PublicationError, "without the registered claim"):
                    self._validate()
            target.unlink()

    def test_registry_and_showcase_residue_require_the_claim(self):
        for relative, residue in (
                (gate.EVIDENCE_REL,
                 "\n  - id: {}\n".format(gate.EVIDENCE_ID)),
                (gate.NONCLAIMS_REL,
                 "\n  - id: {}\n".format(gate.NONCLAIM_ID)),
                (gate.SHOWCASE_REL,
                 "\n{}\n".format(gate.CHART_REL.as_posix()))):
            with self.subTest(path=relative):
                self._copy_provenance()
                path = self.root / relative
                path.write_text(
                    path.read_text(encoding="utf-8") + residue,
                    encoding="utf-8",
                )
                with self.assertRaisesRegex(
                        gate.PublicationError, "without the registered claim"):
                    self._validate()
                shutil.rmtree(self.root)
                self.root.mkdir()

    def test_missing_validator_or_evidence_fails(self):
        self._published_fixture()
        (self.root / gate.VALIDATOR_REL).unlink()
        with self.assertRaisesRegex(gate.PublicationError, "is missing"):
            self._validate()

    def test_existing_claim_mutation_fails(self):
        self._published_fixture()
        path = self.root / gate.CLAIMS_REL
        path.write_text(
            path.read_text(encoding="utf-8").replace(
                "unit: contiguous 512-bit AXI W beats",
                "unit: contiguous 64-bit AXI W beats",
            ),
            encoding="utf-8",
        )
        with self.assertRaisesRegex(gate.PublicationError, "protected"):
            self._validate()

    def test_resume_eligibility_mutation_fails(self):
        self._published_fixture()
        path = self.root / gate.CLAIMS_REL
        text = path.read_text(encoding="utf-8").replace(
            "resume_eligible: false", "resume_eligible: true"
        )
        path.write_text(text, encoding="utf-8")
        with self.assertRaisesRegex(gate.PublicationError, "resume_eligible"):
            self._validate()

    def test_untrusted_source_ref_fails(self):
        self._published_fixture()
        path = self.root / gate.CLAIMS_REL
        path.write_text(
            path.read_text(encoding="utf-8").replace(
                gate.TRUSTED_FLOW_AS_RUN_COMMIT, "b" * 40, 1
            ),
            encoding="utf-8",
        )
        with self.assertRaisesRegex(
                gate.PublicationError, "trusted flow-as-run commit"):
            self._validate()

    def test_decoy_resume_eligibility_text_does_not_bypass_actual_value(self):
        self._published_fixture()
        path = self.root / gate.CLAIMS_REL
        text = path.read_text(encoding="utf-8").replace(
            "    resume_eligible: false",
            "    resume_eligible: true\n"
            '    note: "resume_eligible: false"',
        )
        path.write_text(text, encoding="utf-8")
        with self.assertRaises(gate.PublicationError):
            self._validate()

    def test_deleted_required_rtl_input_fails(self):
        self._published_fixture()
        (self.root / "rtl/tx/dma_axi_read_prefetch.v").unlink()
        with self.assertRaisesRegex(gate.PublicationError, "is missing"):
            self._validate()

    def test_checked_out_source_must_match_source_ref(self):
        self._published_fixture()
        path = self.root / "rtl/tx/dma_axi_read_prefetch.v"
        path.write_text(
            path.read_text(encoding="utf-8") + "\n// post-run mutation\n",
            encoding="utf-8",
        )
        with self.assertRaisesRegex(
                gate.PublicationError, "differs from source_ref"):
            self._validate()

    def test_publication_adapted_repaired_test_may_differ_from_as_run(self):
        self._published_fixture()
        self.assertEqual(
            gate.PUBLICATION_ADAPTED_SOURCE_PATHS,
            frozenset({
                "flows/scripts/test_validate_dma_async64_throughput_repaired.py",
            }),
        )
        path = self.root / next(iter(gate.PUBLICATION_ADAPTED_SOURCE_PATHS))
        path.write_text(
            path.read_text(encoding="utf-8") +
            "\n# public-package fixture adapter\n",
            encoding="utf-8",
        )
        self.assertEqual(
            self._validate(),
            "VERIFIED_RTL_SIMULATION_PUBLISHED",
        )

    def test_unmodified_filelist_cannot_hide_compiled_source_drift(self):
        self._published_fixture()
        path = self.root / "rtl/tx/dma_tx_engine.v"
        path.write_text(
            path.read_text(encoding="utf-8") + "\n// post-run mutation\n",
            encoding="utf-8",
        )
        with self.assertRaisesRegex(
                gate.PublicationError, "differs from source_ref"):
            self._validate()

    def test_existing_showcase_binding_mutation_fails(self):
        self._published_fixture()
        path = self.root / gate.SHOWCASE_REL
        manifest = json.loads(path.read_text(encoding="utf-8"))
        manifest["assets"][0]["claim_ids"] = ["rewritten_claim"]
        path.write_text(json.dumps(manifest), encoding="utf-8")
        with self.assertRaisesRegex(gate.PublicationError, "existing showcase"):
            self._validate()

    def test_existing_showcase_input_digest_must_match_source(self):
        self._published_fixture()
        path = self.root / gate.SHOWCASE_REL
        manifest = json.loads(path.read_text(encoding="utf-8"))
        manifest["assets"][0]["inputs"][0]["sha256"] = "0" * 64
        path.write_text(json.dumps(manifest), encoding="utf-8")
        with self.assertRaisesRegex(gate.PublicationError, "input hash mismatch"):
            self._validate()

    def test_head_owned_validator_cannot_accept_mutated_numeric_evidence(self):
        self._published_fixture()
        path = self.root / gate.PACKAGE_REL / "points.csv"
        path.write_text("forged numeric authority\n", encoding="utf-8")
        manifest_path = self.root / gate.PACKAGE_REL / "manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["files"]["points.csv"] = gate._sha256(path.read_bytes())
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        for relative in (gate.VALIDATOR_REL, gate.BLOCKED_VALIDATOR_REL):
            (self.root / relative).write_text(
                "import sys\nsys.exit(0)\n", encoding="utf-8"
            )
        with self.assertRaisesRegex(gate.PublicationError, "trusted throughput"):
            self._validate(execute_validators=True)

    def test_chart_rejects_unregistered_measurement(self):
        self._published_fixture()
        chart_path = self.root / gate.CHART_REL
        text = chart_path.read_text(encoding="utf-8").replace(
            "</svg>", "<text>Board throughput 9999 GB/s</text></svg>"
        )
        chart_path.write_text(text, encoding="utf-8")
        manifest_path = self.root / gate.SHOWCASE_REL
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["assets"][-1]["sha256"] = gate._sha256(
            chart_path.read_bytes()
        )
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        with self.assertRaisesRegex(gate.PublicationError, "unauthorized measurement"):
            self._validate()

    def test_readme_change_outside_bounded_block_fails(self):
        self._published_fixture()
        path = self.root / "README.en.md"
        path.write_text(
            path.read_text(encoding="utf-8").replace(
                "# SLVC DMA", "# Replaced Homepage", 1
            ),
            encoding="utf-8",
        )
        with self.assertRaisesRegex(gate.PublicationError, "protected homepage"):
            self._validate()

    def test_markdown_image_inside_readme_block_fails(self):
        self._published_fixture()
        path = self.root / "README.en.md"
        path.write_text(
            path.read_text(encoding="utf-8").replace(
                gate.README_END,
                "![extra chart]({})\n{}".format(
                    gate.CHART_REL.as_posix(), gate.README_END
                ),
                1,
            ),
            encoding="utf-8",
        )
        with self.assertRaisesRegex(gate.PublicationError, "payload mismatch"):
            self._validate()

    def test_hidden_only_readme_boundary_fails(self):
        self._published_fixture()
        path = self.root / "README.en.md"
        path.write_text(
            path.read_text(encoding="utf-8").replace(
                "Dual-platform RTL simulation:",
                "<!-- Dual-platform RTL simulation: -->",
                1,
            ),
            encoding="utf-8",
        )
        with self.assertRaisesRegex(
                gate.PublicationError, "visible RTL-simulation boundary"):
            self._validate()

    def test_exact_readme_block_inside_code_fence_fails(self):
        self._published_fixture()
        path = self.root / "README.en.md"
        text = path.read_text(encoding="utf-8")
        protected, block = gate._bounded_block(
            text, gate.README_START, gate.README_END, str(path), True
        )
        self.assertEqual(protected.count("```bash\n"), 1)
        path.write_text(
            protected.replace("```bash\n", "```bash\n" + block, 1),
            encoding="utf-8",
        )
        with self.assertRaisesRegex(
                gate.PublicationError, "structural position mismatch"):
            self._validate()

    def test_result_block_rejects_extra_measurement(self):
        self._published_fixture()
        path = self.root / "docs/en/results.md"
        path.write_text(
            path.read_text(encoding="utf-8").replace(
                gate.RESULTS_END,
                "Measured board throughput: 9999 GB/s.\n{}".format(
                    gate.RESULTS_END
                ),
                1,
            ),
            encoding="utf-8",
        )
        with self.assertRaisesRegex(gate.PublicationError, "payload mismatch"):
            self._validate()

    def test_package_readme_rejects_extra_claim(self):
        self._published_fixture()
        path = self.root / gate.PACKAGE_REL / "README.md"
        path.write_text(
            path.read_text(encoding="utf-8") +
            "\nMeasured FPGA throughput: 9999 GB/s.\n",
            encoding="utf-8",
        )
        manifest_path = self.root / gate.PACKAGE_REL / "manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        digest = gate._sha256(path.read_bytes())
        manifest["document_sha256"] = digest
        manifest["files"]["README.md"] = digest
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        with self.assertRaisesRegex(
                gate.PublicationError, "README payload mismatch"):
            self._validate()

    def test_package_manifest_rejects_extra_claim_field(self):
        self._published_fixture()
        path = self.root / gate.PACKAGE_REL / "manifest.json"
        manifest = json.loads(path.read_text(encoding="utf-8"))
        manifest["measured_fpga_gbps"] = "9999"
        path.write_text(json.dumps(manifest), encoding="utf-8")
        with self.assertRaisesRegex(
                gate.PublicationError, "manifest field set mismatch"):
            self._validate()

    def test_showcase_generator_replacement_fails(self):
        self._published_fixture()
        path = self.root / "flows/scripts/generate_showcase_assets.py"
        path.write_text("raise SystemExit(0)\n", encoding="utf-8")
        with self.assertRaisesRegex(
                gate.PublicationError, "base-owned showcase generator"):
            self._validate()

    def test_result_marker_without_claim_is_publication_sentinel(self):
        self._copy_provenance()
        path = self.root / "docs/en/results.md"
        self._append(
            path,
            gate.RESULTS_START + "\nUnsupported.\n" + gate.RESULTS_END + "\n",
        )
        with self.assertRaisesRegex(gate.PublicationError, "without the registered claim"):
            self._validate()

    def test_chart_cannot_be_numeric_authority(self):
        self._published_fixture()
        path = self.root / gate.SHOWCASE_REL
        manifest = json.loads(path.read_text(encoding="utf-8"))
        manifest["assets"][-1]["numeric_authority"] = True
        path.write_text(json.dumps(manifest), encoding="utf-8")
        with self.assertRaisesRegex(gate.PublicationError, "numeric authority"):
            self._validate()


if __name__ == "__main__":
    unittest.main()
