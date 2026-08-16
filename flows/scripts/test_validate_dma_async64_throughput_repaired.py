from __future__ import print_function

import csv
import json
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

from flows.scripts import run_dma_async64_throughput_matrix as runner
from flows.scripts import validate_dma_async64_throughput_repaired as validator


PUBLIC_PACKAGE_REL = Path(
    "evidence/throughput_simulation/async64_end_to_end"
)
HISTORICAL_EVIDENCE_COMMIT = (
    "5ca6911cbe0c24ec4d283cfcc909b76fe29df0a3"
)
HISTORICAL_FLOW_COMMIT = "c82118cfbf28633d82a315925a390143c91ea117"
ADAPTED_SOURCE_RELS = {
    Path("flows/scripts/test_validate_dma_async64_throughput_repaired.py"),
}


class Async64MatrixRunnerSourceIdentityTests(unittest.TestCase):
    HEAD = "1" * 40
    OTHER = "2" * 40

    @mock.patch.object(runner, "git_status", return_value="")
    @mock.patch.object(runner, "git_commit", return_value=HEAD)
    @mock.patch.object(runner, "git_head", return_value=HEAD)
    def test_accepts_clean_matching_checkout(self, _head, _commit, _status):
        self.assertEqual(
            runner.validate_source_checkout(Path("."), self.HEAD), self.HEAD
        )

    @mock.patch.object(runner, "git_status", return_value=" M rtl/source.v")
    @mock.patch.object(runner, "git_commit", return_value=HEAD)
    @mock.patch.object(runner, "git_head", return_value=HEAD)
    def test_rejects_dirty_checkout(self, _head, _commit, _status):
        with self.assertRaises(runner.RunError):
            runner.validate_source_checkout(Path("."), self.HEAD)

    @mock.patch.object(runner, "git_status", return_value="")
    @mock.patch.object(runner, "git_commit", return_value=OTHER)
    @mock.patch.object(runner, "git_head", return_value=HEAD)
    def test_rejects_mismatched_source_commit(self, _head, _commit, _status):
        with self.assertRaises(runner.RunError):
            runner.validate_source_checkout(Path("."), self.OTHER)

    def test_rejects_noncanonical_source_commit(self):
        with mock.patch.object(runner, "git_head", return_value=self.HEAD):
            with self.assertRaises(runner.RunError):
                runner.validate_source_checkout(Path("."), "HEAD")

    def test_revalidates_source_around_each_simulation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "source"
            output = Path(directory) / "output"
            (root / "modelsim").mkdir(parents=True)
            point = runner.matrix_points()[0]
            args = SimpleNamespace(
                root=str(root), output_dir=str(output),
                source_commit=self.HEAD, points=point["point_id"],
                suite="matrix", platform="windows", vsim="vsim",
                force=False, keep_going=True,
            )

            class FakeProcess(object):
                def __init__(self, handle):
                    self.handle = handle

                def wait(self):
                    self.handle.write((
                        runner.POINT_MARKER + " case=test\n" +
                        runner.PASS_MARKER + "\n"
                    ).encode("utf-8"))
                    self.handle.flush()
                    return 0

            def fake_popen(*_args, **kwargs):
                return FakeProcess(kwargs["stdout"])

            with mock.patch.object(
                    runner, "validate_source_checkout",
                    return_value=self.HEAD) as source_check, mock.patch.object(
                    runner, "command_output",
                    return_value=runner.EXPECTED_SIMULATORS["windows"]), \
                    mock.patch.object(runner, "matrix_points",
                                      return_value=[point]), \
                    mock.patch.object(runner.subprocess, "Popen",
                                      side_effect=fake_popen):
                self.assertEqual(runner.run(args), 0)
            self.assertEqual(source_check.call_count, 4)

    def test_rejects_source_change_after_simulation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "source"
            output = Path(directory) / "output"
            (root / "modelsim").mkdir(parents=True)
            point = runner.matrix_points()[0]
            args = SimpleNamespace(
                root=str(root), output_dir=str(output),
                source_commit=self.HEAD, points=point["point_id"],
                suite="matrix", platform="windows", vsim="vsim",
                force=False, keep_going=True,
            )

            class FakeProcess(object):
                def wait(self):
                    return 0

            with mock.patch.object(
                    runner, "validate_source_checkout",
                    side_effect=(self.HEAD, self.HEAD,
                                 runner.RunError("source changed"))), \
                    mock.patch.object(
                        runner, "command_output",
                        return_value=runner.EXPECTED_SIMULATORS["windows"]), \
                    mock.patch.object(runner, "matrix_points",
                                      return_value=[point]), \
                    mock.patch.object(runner.subprocess, "Popen",
                                      return_value=FakeProcess()):
                with self.assertRaisesRegex(runner.RunError, "source changed"):
                    runner.run(args)
            self.assertFalse((output / "run_index.json").exists())


class Async64RunIndexContractTests(unittest.TestCase):
    FLOW_COMMIT = "3" * 40

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.run_dir = Path(self.temp.name)
        self.contract = runner.matrix_points()[0]
        self.simulator = validator.EXPECTED_SIMULATORS["windows"]
        self.record = dict(self.contract)
        self.record.update({
            "platform": "windows",
            "simulator": self.simulator,
            "source_commit": self.FLOW_COMMIT,
            "returncode": 0,
            "status": "PASS",
            "log_file": self.contract["point_id"] + ".log",
            "log_sha256": "4" * 64,
            "log_size_bytes": 1,
        })

    def tearDown(self):
        self.temp.cleanup()

    def write_index(self):
        (self.run_dir / "run_index.json").write_text(
            json.dumps({
                "schema_version": 1,
                "suite": "matrix",
                "platform": "windows",
                "simulator": self.simulator,
                "source_commit": self.FLOW_COMMIT,
                "seed": 71,
                "records": [self.record],
            }),
            encoding="utf-8",
        )

    def test_accepts_exact_run_index_contract(self):
        self.write_index()
        validator.load_run_index(
            self.run_dir, "windows", self.FLOW_COMMIT,
            [self.contract], "matrix",
        )

    def test_rejects_run_index_payload_argument_drift(self):
        self.record["payload_arg_bytes"] += 64
        self.write_index()
        with self.assertRaisesRegex(
                validator.ValidationError, "payload_arg_bytes mismatch"):
            validator.load_run_index(
                self.run_dir, "windows", self.FLOW_COMMIT,
                [self.contract], "matrix",
            )

    def test_rejects_platform_simulator_masquerade(self):
        self.simulator = validator.EXPECTED_SIMULATORS["linux"]
        self.record["simulator"] = self.simulator
        self.write_index()
        with self.assertRaisesRegex(
                validator.ValidationError, "simulator mismatch"):
            validator.load_run_index(
                self.run_dir, "windows", self.FLOW_COMMIT,
                [self.contract], "matrix",
            )


class Async64HomepageBoundaryTests(unittest.TestCase):
    def test_throughput_label_is_visible_in_both_readmes(self):
        root = Path(__file__).resolve().parents[2]
        expected = {
            "README.md": "双平台 RTL 仿真",
            "README.en.md": "Dual-platform RTL simulation",
        }
        start = "throughput-publication:slvc_dma_async64_end_to_end_rtl_sim_throughput:readme:start"
        end = "throughput-publication:slvc_dma_async64_end_to_end_rtl_sim_throughput:readme:end"
        for name, label in expected.items():
            text = (root / name).read_text(encoding="utf-8")
            block = text.split(start, 1)[1].split(end, 1)[0]
            visible = re.sub(r"<!--.*?-->", "", block, flags=re.S)
            self.assertIn(label, visible)


def historical_blob(root, relative, commit=HISTORICAL_EVIDENCE_COMMIT):
    return subprocess.check_output(
        ["git", "-c", "safe.directory={}".format(root.as_posix()),
         "show", "{}:{}".format(commit, relative)],
        cwd=str(root), stderr=subprocess.STDOUT,
    )


class Async64RepairedThroughputEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.source_root = Path(__file__).resolve().parents[2]
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        for rel in validator.SOURCE_PATHS:
            target = self.root / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            if Path(rel) in ADAPTED_SOURCE_RELS:
                target.write_bytes(historical_blob(
                    self.source_root, Path(rel).as_posix(),
                    HISTORICAL_FLOW_COMMIT,
                ))
            else:
                shutil.copy2(str(self.source_root / rel), str(target))
        package = self.root / validator.PACKAGE_REL
        package.mkdir(parents=True, exist_ok=True)
        for source in (self.source_root / PUBLIC_PACKAGE_REL).iterdir():
            if source.name in {"README.md", "manifest.json"}:
                continue
            shutil.copy2(str(source), str(package / source.name))
        for name in ("README.md", "manifest.json"):
            relative = validator.PACKAGE_REL / name
            (package / name).write_bytes(
                historical_blob(self.source_root, relative.as_posix())
            )
        target_doc = self.root / validator.DOC_REL
        target_doc.parent.mkdir(parents=True, exist_ok=True)
        target_doc.write_bytes(
            historical_blob(self.source_root, validator.DOC_REL.as_posix())
        )

    def tearDown(self):
        self.temp.cleanup()

    def validate(self):
        return validator.validate(self.root)

    def manifest(self):
        path = self.root / validator.MANIFEST_REL
        return path, json.loads(path.read_text(encoding="utf-8"))

    def write_manifest(self, data):
        path = self.root / validator.MANIFEST_REL
        path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n",
                        encoding="utf-8")

    def mutate_manifest(self, callback):
        _, data = self.manifest()
        callback(data)
        self.write_manifest(data)

    def mutate_csv(self, rel, callback):
        path = self.root / rel
        with path.open("r", encoding="utf-8", newline="") as handle:
            reader = csv.DictReader(handle)
            header = reader.fieldnames
            rows = list(reader)
        callback(rows)
        with path.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=header, lineterminator="\n")
            writer.writeheader()
            writer.writerows(rows)
        _, data = self.manifest()
        data["files"][path.name] = validator.sha256_file(path)
        self.write_manifest(data)

    def mutate_json_file(self, rel, callback):
        path = self.root / rel
        data = json.loads(path.read_text(encoding="utf-8"))
        callback(data)
        path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n",
                        encoding="utf-8")
        _, manifest = self.manifest()
        manifest["files"][path.name] = validator.sha256_file(path)
        self.write_manifest(manifest)

    def assert_rejected(self):
        with self.assertRaises(validator.ValidationError):
            self.validate()

    def test_valid_repaired_package(self):
        result = self.validate()
        self.assertEqual(result["points"], 66)
        self.assertEqual(result["matrix"], 28)
        self.assertEqual(result["ladder"], 5)

    def test_rejects_public_promotion(self):
        self.mutate_manifest(lambda data: data.__setitem__(
            "public_claim_eligible", True))
        self.assert_rejected()

    def test_rejects_resume_promotion(self):
        self.mutate_manifest(lambda data: data.__setitem__("resume_eligible", True))
        self.assert_rejected()

    def test_rejects_claim_id(self):
        self.mutate_manifest(lambda data: data.__setitem__(
            "claim_id", "async64_board_throughput"))
        self.assert_rejected()

    def test_rejects_decimal_score_drift(self):
        self.mutate_csv(validator.METRICS_REL, lambda rows: rows[0].__setitem__(
            "mbps_per_mhz", "8.000000"))
        self.assert_rejected()

    def test_rejects_nonzero_protocol_error(self):
        self.mutate_csv(validator.POINTS_REL, lambda rows: rows[0].__setitem__(
            "protocol_error", "1"))
        self.assert_rejected()

    def test_rejects_payload_bytes_contract_mismatch(self):
        def mutate(rows):
            rows[0]["payload_bytes"] = str(int(rows[0]["payload_bytes"]) + 64)

        self.mutate_csv(validator.POINTS_REL, mutate)
        with self.assertRaises(validator.ValidationError) as context:
            self.validate()
        self.assertIn("point contract mismatch", str(context.exception))

    def test_rejects_missing_platform_point(self):
        self.mutate_csv(validator.POINTS_REL, lambda rows: rows.pop())
        self.assert_rejected()

    def test_rejects_trace_mismatch(self):
        self.mutate_csv(validator.VERIFICATION_REL, lambda rows: rows[0].__setitem__(
            "semantic_trace_sha256", "0" * 64))
        self.assert_rejected()

    def test_rejects_ladder_trace_mismatch(self):
        self.mutate_csv(validator.LADDER_REL, lambda rows: rows[0].__setitem__(
            "semantic_trace_sha256", "0" * 64))
        self.assert_rejected()

    def test_rejects_pass_marker_erasure(self):
        self.mutate_csv(validator.VERIFICATION_REL, lambda rows: rows[0].__setitem__(
            "pass_marker_count", "0"))
        self.assert_rejected()

    def test_rejects_artifact_publication(self):
        self.mutate_csv(validator.ARTIFACTS_REL, lambda rows: rows[0].__setitem__(
            "published", "true"))
        self.assert_rejected()

    def test_rejects_fairness_loss(self):
        self.mutate_csv(validator.FAIRNESS_REL, lambda rows: rows[0].__setitem__(
            "completions", "63"))
        self.assert_rejected()

    def test_rejects_c2b4_identity_drift(self):
        self.mutate_json_file(validator.IDENTITY_REL, lambda data:
                              data.__setitem__("identity_equal", False))
        self.assert_rejected()

    def test_rejects_unhashed_c2b4_filelist_member(self):
        def mutate(data):
            member = data["c2b4_source_members"][0]
            data["files"] = [record for record in data["files"]
                             if record["path"] != member]

        self.mutate_json_file(validator.IDENTITY_REL, mutate)
        with self.assertRaisesRegex(
                validator.ValidationError, "not all hash-bound"):
            self.validate()

    def test_rejects_c2b4_rerun_claim(self):
        self.mutate_manifest(lambda data: data.__setitem__(
            "c2b4_physical_rerun_performed", True))
        self.assert_rejected()

    def test_rejects_source_hash_drift(self):
        self.mutate_manifest(lambda data: data["sources"][0].__setitem__(
            "sha256", "0" * 64))
        self.assert_rejected()

    def test_rejects_hp0_model_as_board_measurement(self):
        self.mutate_manifest(lambda data: data["boundaries"].__setitem__(
            "hp0_shared_is_board_measurement", True))
        self.assert_rejected()

    def test_rejects_sameclock_claim_reuse(self):
        self.mutate_manifest(lambda data: data["boundaries"].__setitem__(
            "sameclock512_64_bytes_per_cycle_claim_reused", True))
        self.assert_rejected()

    def test_rejects_model_limit_drift(self):
        self.mutate_manifest(lambda data: data["main_point"].__setitem__(
            "payload_only_model_limit_mbps_per_mhz", "8.000000"))
        self.assert_rejected()

    def test_rejects_private_path_injection(self):
        path = self.root / validator.DOC_REL
        path.write_text(path.read_text(encoding="utf-8") +
                        "\nC:/Users/example/private.log\n", encoding="utf-8")
        self.assert_rejected()


if __name__ == "__main__":
    unittest.main()
