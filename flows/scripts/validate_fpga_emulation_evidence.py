#!/usr/bin/env python3
"""Fail-closed validator for the bounded U5 FPGA board observation."""

from __future__ import print_function

import argparse
import csv
import hashlib
import json
import re
import subprocess
import sys
from decimal import Decimal, InvalidOperation, ROUND_HALF_EVEN
from pathlib import Path


CLAIM_ID = "slvc_dma_u5_sync_hp0_loopback_board_throughput"
EVIDENCE_ID = "slvc_dma_u5_sync_hp0_loopback_summary"
NONCLAIM_ID = "slvc_dma_u5_sync_hp0_loopback_not_transferable"
BRAM_CLAIM_ID = "slvc_dma_u5_13ch_bram_architecture_comparison"
README_START = (
    "<!-- fpga-emulation-publication:"
    "slvc_dma_u5_sync_hp0_loopback_board_throughput:readme:start -->"
)
README_END = (
    "<!-- fpga-emulation-publication:"
    "slvc_dma_u5_sync_hp0_loopback_board_throughput:readme:end -->"
)
RESULTS_START = (
    "<!-- fpga-emulation-publication:"
    "slvc_dma_u5_sync_hp0_loopback_board_throughput:start -->"
)
RESULTS_END = (
    "<!-- fpga-emulation-publication:"
    "slvc_dma_u5_sync_hp0_loopback_board_throughput:end -->"
)
BRAM_README_START = (
    "<!-- fpga-bram-publication:"
    "slvc_dma_u5_13ch_bram_architecture_comparison:readme:start -->"
)
BRAM_README_END = (
    "<!-- fpga-bram-publication:"
    "slvc_dma_u5_13ch_bram_architecture_comparison:readme:end -->"
)
BRAM_RESULTS_START = (
    "<!-- fpga-bram-publication:"
    "slvc_dma_u5_13ch_bram_architecture_comparison:start -->"
)
BRAM_RESULTS_END = (
    "<!-- fpga-bram-publication:"
    "slvc_dma_u5_13ch_bram_architecture_comparison:end -->"
)
SOURCE_REF = "144231a9694b1a6f4698082a333ceb39d7029d08"
PUBLIC_SOURCE_REF = "efb16bb4456a76f87a1dfcf0dc1c6ab6d40240c7"
PACKAGE_REL = Path("evidence/fpga_emulation/u5_sync_hp0_loopback")
SUMMARY_REL = Path("evidence/slvc_dma_u5_sync_hp0_loopback_summary.yaml")
BENCHMARK_REL = Path("fpga/u5/benchmark")
CLAIMS_REL = Path("provenance/claims.yaml")
EVIDENCE_REL = Path("provenance/evidence.yaml")
NONCLAIMS_REL = Path("provenance/nonclaims.yaml")
SUMMARY_SHA256 = "c02bef90c8e92e3c6e065b01ed70bf27ab2eedcea6a9e5c9433dfb2c89d4d004"
PROTECTED_SOURCE_TREE_SHA256 = (
    "acc99475ff2463dcd5302528282dcff906b3f68c8fc57e598a122115c8ab7901"
)

CLAIM_FIXED = {
    "profile": "slvc_dma_u5_sync_hp0_loopback_fpga",
    "statement": (
        "In one 1024 x 4 KiB U5 synchronous TX0-to-RX0 loopback run at "
        "100 MHz, operator-transcribed debugger counters imply a post-start-"
        "write-return completion-window payload rate of 1.558722 MB/s/MHz "
        "(155.872225 MB/s, 1.246978 Gb/s)."
    ),
    "metric": "debugger_transcribed_post_start_completion_payload_rate",
    "value": "1.558722",
    "unit": "MB/s/MHz",
    "benchmark": "single 1024 x 4096-byte U5 TX0-to-RX0 loopback observation",
    "configuration": (
        "13 RX/13 TX contexts; synchronous 100 MHz PL-local loopback; "
        "512-bit AXIS register slice; existing 64-bit PS HP0 port"
    ),
    "source_ref": SOURCE_REF,
    "tool": "Vivado/SDK 2018.3",
    "evidence": [EVIDENCE_ID],
    "status": "partial",
    "caveat": (
        "FPGA_DEBUGGER_TRANSCRIBED_SINGLE_RUN; launch latency, independent "
        "screenshot/memory export, source-to-binary build traceability, "
        "automated UART transcript, steady-state capture, repeatability "
        "statistics, Async64 CDC board result, DDR peak, Fmax, 64 B/cycle "
        "Writer result, and ASIC result are not included."
    ),
    "resume_eligible": False,
    "public": True,
}
EVIDENCE_FIXED = {
    "path": str(SUMMARY_REL).replace("\\", "/"),
    "type": "fpga_debugger_transcribed_single_run",
    "source_ref": SOURCE_REF,
    "tool": "Vivado/SDK 2018.3",
    "claims": [CLAIM_ID],
    "sha256": SUMMARY_SHA256,
    "public": True,
}
NONCLAIM_FIXED = {
    "profile": "slvc_dma_u5_sync_hp0_loopback_fpga",
    "statement": (
        "This single U5 observation is not launch-to-completion hardware end-"
        "to-end throughput, an independently retained debugger capture, "
        "source-to-binary build traceability, Async64 CDC board testing, "
        "Aurora performance, DDR peak, FPGA Fmax, the 64 B/cycle Writer "
        "result, ASIC evidence, or a statistical repeatability result."
    ),
    "reason": (
        "The measured profile is a 13 RX/13 TX, 100 MHz synchronous PL-local "
        "loopback over the existing 64-bit HP0 port. The timer starts after "
        "the descriptor-start write returns, and the values were transcribed "
        "once from the SDK debugger after the timing window and correctness "
        "gates."
    ),
    "status": "not_claimed",
    "public": True,
}

EXPECTED_PACKAGE_FILES = frozenset({
    "README.md", "debugger_capture_transcript.txt",
    "artifacts.csv",
    "derived_metrics.csv",
    "manifest.json",
    "raw_counters.csv",
    "sanitized_sdk_log.txt",
    "source_delta.diff",
    "source_identity.json",
})
EXPECTED_BENCHMARK_FILES = frozenset({
    "README.md", "dma_loopback_regs.h", "dma_mmio_diag.c",
    "dma_mmio_diag.h", "helloworld.c",
})
FIXED_FILE_SHA256 = {
    PACKAGE_REL / "README.md": "1a9d9e279e0ebdec2b0977d667be6ea14dff421451dea5fa0a8045041094fdb8",
    PACKAGE_REL / "artifacts.csv": "1efa89689bfcd11dfcc888f41b4202ed175ffa9a328d640f55b5ab89fb91da64",
    PACKAGE_REL / "debugger_capture_transcript.txt": "379c2d58970bba2df1e80be6793c8cbe29c516f7be842aa297ffe1caa16c2d03",
    PACKAGE_REL / "derived_metrics.csv": "8c64642d7b53f7e790828d84891ae5d269b55ca4d0028a2a1372b3607b8550e2",
    PACKAGE_REL / "manifest.json": "11edf278fd477a02951c576e80b013692901097b160369a3e19099ed51462ca7",
    PACKAGE_REL / "raw_counters.csv": "ffb63449019d1bb3ff04a145ce553e842a67335d3e5753c849adadc430be8a6a",
    PACKAGE_REL / "sanitized_sdk_log.txt": "329c4d2e251e40a9671ec2473ff467fa8641f596af6981eb728c2a008720f3b0",
    PACKAGE_REL / "source_delta.diff": "c48c5b8e27b2caf22851c1a2630f1434b878d922ed44c06592b4cdb982fece59",
    PACKAGE_REL / "source_identity.json": "2341a65aa61a994263951fba9e1cb1890558dc982fa41c6e0a2e8cd3dd214d94",
    BENCHMARK_REL / "README.md": "c6fc52d4cd249afb8f70e27ae5891fc3a9557f3bf993063cd8bacd18dcff80e3",
    BENCHMARK_REL / "helloworld.c": "48f94f9dd87223bbfd1cd58558f7380bdc5f521d36373b5f24cc48b4d351f902",
    BENCHMARK_REL / "dma_loopback_regs.h": "2e78bcae0b4da9065379a3c0612b333abd875c016f2b2d76b0e02ab6d3102467",
    BENCHMARK_REL / "dma_mmio_diag.c": "35954f27b38b8dfce9a8a85e94ab3addcf35960a49d5a97f683bd8288ab5bc8e",
    BENCHMARK_REL / "dma_mmio_diag.h": "5520e1f7637aca1bd4a47928be02433413810d0f5a5932785012fa3046cc42f0",
    SUMMARY_REL: SUMMARY_SHA256,
}
EXPECTED_DOC_BLOCK_SHA256 = {
    Path("README.md"): "5ebed4e9d69e409e3f76c52f476c994e78e1145f7018c0f3a88193e196b918b7",
    Path("README.en.md"): "ba1ab43421fc8415cac07c8e2dca87e214dc57cc7b2d078516510083e1296777",
    Path("docs/zh-CN/results.md"): "eb4b0c5eb402b371f825a9d5caa7d596830dfc39d4daff14ed3cf3c716a69c81",
    Path("docs/en/results.md"): "bcb6f4e007a47670e0d018da1524cc6df7584221ebe6106f76498c0edeca6183",
}
EXPECTED_DOC_LAYOUT_SHA256 = {
    Path("README.md"): (
        "12eeefce45eae3578b83e8f9f67d6d75df53a52bb427ef108c7668901b0c6ff9",
        "9db414fbfa35f7bd6968c8b20b3e06223f69e424e542b803a0b60de6d206fb54",
    ),
    Path("README.en.md"): (
        "1b018fecf67fe85e2d9ee3f7c977974a6324d87e9c4182c2433c7d1ee25a6663",
        "bdf3ef22a0f6d6b5c596a0b1d2113aca213674eb0c601588277ad8580cf5adb2",
    ),
    Path("docs/zh-CN/results.md"): (
        "143800c5ed73680492e19ab8a57f99873a38e7c0cd9c341fc08ba567fb0536d3",
        "a847ac1b9b3049ecc207dfa9d8693fcb8fcd62c79691eb5fa626c277b114725d",
    ),
    Path("docs/en/results.md"): (
        "0e7bcac1fabada3e9fad353bf40dcac617cd14b1afa3fccde8a5a9a840eff32c",
        "a2f7ec67604d61371451ac47f83f23497a0ccb3c0750b8f2c6b6470f3b58c025",
    ),
}
EXPECTED_FPGA_IMPLEMENTATION_SHA256 = {
    Path("docs/zh-CN/fpga_implementation.md"): (
        "d90d439277bc920ce2750a6a86376ce57f44634adadc08c7f2e6fe75951a42cf"
    ),
    Path("docs/en/fpga_implementation.md"): (
        "a687c179c11819c03a11035f4bdc35fc52ddfa6fb10ac9703af4bf58ee0584ef"
    ),
}
UNPUBLISHED_FPGA_IMPLEMENTATION_SHA256 = {
    Path("docs/zh-CN/fpga_implementation.md"): (
        "ffd1fd5dab0faed02a54c38cd7834beb40145ca992648e0f0851c53e7f014de5"
    ),
    Path("docs/en/fpga_implementation.md"): (
        "e15a5b8ea9d5e4af74c65846f30023b240812a9a53826ddf3e46b8205722a4c8"
    ),
}

RAW_ROW = {
    "run_id": "u5_sync_hp0_loopback_1024x4k_20260817_062748_cst",
    "classification": "FPGA_DEBUGGER_TRANSCRIBED_SINGLE_RUN",
    "frame_count": "1024",
    "frame_bytes": "4096",
    "payload_bytes": "4194304",
    "xtime_ticks": "8969535",
    "counts_per_second": "333333343",
    "configured_pl_clock_hz": "100000000",
    "rounded_equivalent_pl_cycles": "2690860",
    "score_milli": "1558",
    "mbps_milli": "155872",
    "gbps_milli": "1246",
    "first_frame_excluded_status": "not_captured",
    "correctness_gate": "passed_before_report_call",
    "debugger_breakpoint_after_timing": "true",
    "uart_capture_status": "tail_incomplete",
    "capture_record": "debugger_capture_transcript.txt",
}
DERIVED_VALUES = {
    "elapsed_seconds": ("0.026908604", "seconds"),
    "equivalent_payload_rate": ("1.558722", "bytes/cycle"),
    "mb_per_s_per_mhz": ("1.558722", "MB/s/MHz"),
    "mb_per_s_at_100mhz": ("155.872225", "MB/s"),
    "gbits_per_s_at_100mhz": ("1.246978", "Gb/s"),
    "hp0_shared_model_efficiency": ("38.968056", "percent"),
}
EXTERNAL_ARTIFACTS = {
    "u5_bitstream": ("7167253", "0aff10f9479ae96b99bb525b42f486d8dd4904b2b88e8057080abf375b7645fa"),
    "u5_throughput_elf": ("276188", "4c1cfd143641d88e405c7d6384a9f17f629f0416fda98c3aa37e76730b174438"),
    "u5_original_sdk_log": ("112593", "7059bf95c533e4ee0cc47c1c018bde70246621a1c79071d8f9ecb03e83777ec4"),
    "u5_reference_helloworld": ("34607", "48f94f9dd87223bbfd1cd58558f7380bdc5f521d36373b5f24cc48b4d351f902"),
    "u5_debugger_transcript": ("1026", "379c2d58970bba2df1e80be6793c8cbe29c516f7be842aa297ffe1caa16c2d03"),
}
SENSITIVE_PATTERNS = (
    re.compile(r"[A-Za-z]:[\\/]"),
    re.compile(r"(?i)ichigo"),
    re.compile(r"(?i)platform cable"),
    re.compile(r"136202079204c3"),
    re.compile(r"(?i)COM[0-9]+"),
    re.compile(r"127\.0\.0\.1"),
)


class EvidenceError(RuntimeError):
    pass


def _fail(message):
    raise EvidenceError(message)


def _sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _read_text(path):
    try:
        return path.read_text(encoding="utf-8")
    except OSError as error:
        _fail("cannot read {}: {}".format(path, error))


def _item_block(text, item_id):
    pattern = re.compile(
        r"(?ms)^  - id: " + re.escape(item_id) + r"\n.*?(?=^  - id: |\Z)"
    )
    matches = list(pattern.finditer(text))
    if len(matches) != 1:
        _fail("expected exactly one {} item".format(item_id))
    return matches[0].group(0)


def _yaml_scalar(raw, context):
    if raw.startswith('"'):
        try:
            value = json.loads(raw)
        except (TypeError, ValueError) as error:
            _fail("{} has invalid quoted scalar: {}".format(context, error))
        if not isinstance(value, str):
            _fail("{} quoted scalar must be text".format(context))
        return value
    if raw == "true":
        return True
    if raw == "false":
        return False
    if not raw or raw != raw.strip():
        _fail("{} has invalid scalar".format(context))
    return raw


def _parse_registry_record(text, item_id):
    block = _item_block(text, item_id)
    fields = {}
    active_list = None
    for line in block.splitlines()[1:]:
        scalar = re.fullmatch(r"    ([a-z][a-z0-9_]*):(?: (.*))?", line)
        if scalar:
            key, raw = scalar.groups()
            if key in fields:
                _fail("{} has duplicate {}".format(item_id, key))
            if raw is None:
                fields[key] = []
                active_list = key
            else:
                fields[key] = _yaml_scalar(raw, "{}.{}".format(item_id, key))
                active_list = None
            continue
        item = re.fullmatch(r"      - (.+)", line)
        if item and active_list is not None:
            fields[active_list].append(
                _yaml_scalar(item.group(1), "{}.{}".format(item_id, active_list))
            )
            continue
        _fail("{} has unsupported registry syntax".format(item_id))
    return fields


def _require_record(actual, expected, context):
    if set(actual) != set(expected):
        _fail("{} field set mismatch".format(context))
    for field, value in expected.items():
        if actual.get(field) != value:
            _fail("{} fixed {} mismatch".format(context, field))


def _read_csv(path):
    try:
        with path.open("r", encoding="utf-8", newline="") as stream:
            return list(csv.DictReader(stream))
    except OSError as error:
        _fail("cannot read {}: {}".format(path, error))


def _decimal(raw, context):
    try:
        return Decimal(str(raw))
    except (InvalidOperation, ValueError):
        _fail("{} is not decimal".format(context))


def derive_metrics(raw):
    payload = _decimal(raw["payload_bytes"], "payload_bytes")
    ticks = _decimal(raw["xtime_ticks"], "xtime_ticks")
    counts = _decimal(raw["counts_per_second"], "counts_per_second")
    pl_hz = _decimal(raw["configured_pl_clock_hz"], "configured_pl_clock_hz")
    if min(payload, ticks, counts, pl_hz) <= 0:
        _fail("throughput counters must be positive")
    rounded_equivalent_cycles = int(
        (int(ticks) * int(pl_hz) + int(counts) // 2) // int(counts)
    )
    if rounded_equivalent_cycles != int(raw["rounded_equivalent_pl_cycles"]):
        _fail("equivalent PL cycle count mismatch")
    elapsed = ticks / counts
    rate = payload * counts / ticks / pl_hz
    mbps = payload * counts / ticks / Decimal(1000000)
    gbps = mbps * Decimal("0.008")
    efficiency = rate / Decimal(4) * Decimal(100)
    values = {
        "elapsed_seconds": elapsed.quantize(Decimal("0.000000001"), rounding=ROUND_HALF_EVEN),
        "equivalent_payload_rate": rate.quantize(Decimal("0.000001"), rounding=ROUND_HALF_EVEN),
        "mb_per_s_per_mhz": rate.quantize(Decimal("0.000001"), rounding=ROUND_HALF_EVEN),
        "mb_per_s_at_100mhz": mbps.quantize(Decimal("0.000001"), rounding=ROUND_HALF_EVEN),
        "gbits_per_s_at_100mhz": gbps.quantize(Decimal("0.000001"), rounding=ROUND_HALF_EVEN),
        "hp0_shared_model_efficiency": efficiency.quantize(Decimal("0.000001"), rounding=ROUND_HALF_EVEN),
    }
    return {key: format(value, "f") for key, value in values.items()}


def _verify_source_control_flow(text):
    if text.count("#define DMA_TEST_MODE DMA_TEST_THROUGHPUT") != 1:
        _fail("reference source test mode mismatch")
    if text.count("#define DMA_THROUGHPUT_FRAME_COUNT 1024U") != 1:
        _fail("reference source frame-count mismatch")
    function_start = text.find("static int dma_throughput_phase(")
    if function_start < 0:
        _fail("reference source is missing dma_throughput_phase")
    text = text[function_start:]
    required = (
        "dma_write_sync(desc + DMA_TX_DESC_CTRL,",
        "XTime_GetTime(&start_time);",
        "poll_throughput_cq(frame_count, start_time",
        "wait_descriptor_complete(frame_count)",
        "wait_rx_used(payload_bytes)",
        "compare_payload(THR_TX_SRC_ADDR, THR_RX_DST_ADDR, payload_bytes)",
        "wait_rx_used(0U)",
        "take_error_snapshot(&after)",
        'xil_printf("THROUGHPUT correctness PASS',
        'report_throughput_window("hardware_end_to_end"',
    )
    positions = []
    for token in required:
        position = text.find(token)
        if position < 0:
            _fail("reference source is missing control-flow token: {}".format(token))
        positions.append(position)
    if positions != sorted(positions):
        _fail("reference source control-flow order mismatch")


def _verify_sensitive_text(path, text):
    for pattern in SENSITIVE_PATTERNS:
        if pattern.search(text):
            _fail("{} contains sensitive identity: {}".format(path, pattern.pattern))


def _verify_git_source_tree(root):
    try:
        data = subprocess.check_output([
            "git", "ls-tree", "-r", PUBLIC_SOURCE_REF, "--",
            "rtl", "configs",
            "flows/manifests", "flows/constraints", "constraints", "filelists",
        ], cwd=str(root))
    except (OSError, subprocess.CalledProcessError) as error:
        _fail("cannot verify protected source tree: {}".format(error))
    digest = hashlib.sha256(data).hexdigest()
    if digest != PROTECTED_SOURCE_TREE_SHA256:
        _fail("production RTL/profile/filelist/constraint tree changed")


def _strip_optional_bram_doc_block(text, relative, authorized):
    if relative in (Path("README.md"), Path("README.en.md")):
        start, end = BRAM_README_START, BRAM_README_END
    elif relative in (
            Path("docs/zh-CN/results.md"), Path("docs/en/results.md"),
            Path("docs/zh-CN/fpga_implementation.md"),
            Path("docs/en/fpga_implementation.md")):
        start, end = BRAM_RESULTS_START, BRAM_RESULTS_END
    else:
        return text
    pattern = re.compile(
        r"(?ms)^" + re.escape(start) + r"\n.*?^" + re.escape(end) + r"\n?"
    )
    matches = list(pattern.finditer(text))
    if len(matches) > 1 or text.count(start) != len(matches) or text.count(end) != len(matches):
        _fail("{} optional FPGA BRAM publication block mismatch".format(relative))
    if not matches:
        return text
    if not authorized:
        _fail("{} contains an FPGA BRAM block without its claim".format(relative))
    match = matches[0]
    return text[:match.start()] + text[match.end():]


def _verify_docs(root, bram_claim_registered):
    files = {
        Path("README.md"): ("单次 FPGA 板级观测", "155.872 MB/s"),
        Path("README.en.md"): ("Single FPGA board observation", "155.872 MB/s"),
        Path("docs/zh-CN/results.md"): ("FPGA 板级单次观测", "1.247 Gb/s"),
        Path("docs/en/results.md"): ("Single FPGA Board Observation", "1.247 Gb/s"),
        Path("docs/zh-CN/fpga_implementation.md"): ("FPGA_DEBUGGER_TRANSCRIBED_SINGLE_RUN", "not retained"),
        Path("docs/en/fpga_implementation.md"): ("FPGA_DEBUGGER_TRANSCRIBED_SINGLE_RUN", "not retained"),
    }
    marker = "<!-- claim:{} maturity:partial -->".format(CLAIM_ID)
    for relative, tokens in files.items():
        text = _read_text(root / relative)
        text = _strip_optional_bram_doc_block(
            text, relative, bram_claim_registered
        )
        for token in tokens:
            if token not in text:
                _fail("{} is missing {}".format(relative, token))
        if relative.name in ("README.md", "README.en.md", "results.md") and marker not in text:
            _fail("{} is missing the FPGA claim marker".format(relative))
    for relative, start, end in (
            (Path("README.md"), README_START, README_END),
            (Path("README.en.md"), README_START, README_END),
            (Path("docs/zh-CN/results.md"), RESULTS_START, RESULTS_END),
            (Path("docs/en/results.md"), RESULTS_START, RESULTS_END)):
        text = _read_text(root / relative)
        pattern = re.compile(
            r"(?ms)^" + re.escape(start) + r"\n.*?^" +
            re.escape(end) + r"\n?"
        )
        matches = list(pattern.finditer(text))
        if (len(matches) != 1 or text.count(start) != 1 or
                text.count(end) != 1 or marker not in matches[0].group(0)):
            _fail("{} FPGA publication block mismatch".format(relative))
        digest = hashlib.sha256(matches[0].group(0).encode("utf-8")).hexdigest()
        if digest != EXPECTED_DOC_BLOCK_SHA256[relative]:
            _fail("{} FPGA publication payload mismatch".format(relative))
        expected_prefix, expected_suffix = EXPECTED_DOC_LAYOUT_SHA256[relative]
        prefix = hashlib.sha256(
            text[:matches[0].start()].encode("utf-8")
        ).hexdigest()
        suffix = hashlib.sha256(
            text[matches[0].end():].encode("utf-8")
        ).hexdigest()
        if prefix != expected_prefix or suffix != expected_suffix:
            _fail("{} FPGA publication position mismatch".format(relative))
    for relative, expected in EXPECTED_FPGA_IMPLEMENTATION_SHA256.items():
        text = _strip_optional_bram_doc_block(
            _read_text(root / relative), relative, bram_claim_registered
        )
        if hashlib.sha256(text.encode("utf-8")).hexdigest() != expected:
            _fail("{} fixed FPGA implementation document mismatch".format(
                relative
            ))


def _verify_unpublished_docs(root, bram_claim_registered):
    for relative, start, end in (
            (Path("README.md"), README_START, README_END),
            (Path("README.en.md"), README_START, README_END),
            (Path("docs/zh-CN/results.md"), RESULTS_START, RESULTS_END),
            (Path("docs/en/results.md"), RESULTS_START, RESULTS_END)):
        text = _read_text(root / relative)
        if start in text or end in text:
            _fail("{} contains FPGA publication markers without its claim".format(
                relative
            ))
    for relative, expected in UNPUBLISHED_FPGA_IMPLEMENTATION_SHA256.items():
        text = _strip_optional_bram_doc_block(
            _read_text(root / relative), relative, bram_claim_registered
        )
        if hashlib.sha256(text.encode("utf-8")).hexdigest() != expected:
            _fail("{} modifies protected unpublished FPGA documentation".format(
                relative
            ))


def validate(root, check_git_identity=True):
    root = Path(root).resolve()
    claims_text = _read_text(root / CLAIMS_REL)
    evidence_text = _read_text(root / EVIDENCE_REL)
    nonclaims_text = _read_text(root / NONCLAIMS_REL)
    claim_present = "  - id: {}\n".format(CLAIM_ID) in claims_text
    bram_claim_registered = "  - id: {}\n".format(BRAM_CLAIM_ID) in claims_text
    payload_present = any((root / path).exists() for path in (
        PACKAGE_REL, SUMMARY_REL, BENCHMARK_REL,
    ))
    related_present = (
        "  - id: {}\n".format(EVIDENCE_ID) in evidence_text or
        "  - id: {}\n".format(NONCLAIM_ID) in nonclaims_text
    )
    if not claim_present:
        if payload_present or related_present:
            _fail("FPGA evidence payload exists without its registered claim")
        _verify_unpublished_docs(root, bram_claim_registered)
        return "FPGA_EMULATION_EVIDENCE_NOT_PUBLISHED"

    _require_record(
        _parse_registry_record(claims_text, CLAIM_ID), CLAIM_FIXED, "FPGA claim"
    )
    _require_record(
        _parse_registry_record(evidence_text, EVIDENCE_ID),
        EVIDENCE_FIXED, "FPGA evidence",
    )
    _require_record(
        _parse_registry_record(nonclaims_text, NONCLAIM_ID),
        NONCLAIM_FIXED, "FPGA nonclaim",
    )

    package_files = {
        str(path.relative_to(root / PACKAGE_REL)).replace("\\", "/")
        for path in (root / PACKAGE_REL).rglob("*") if path.is_file()
    }
    benchmark_files = {
        str(path.relative_to(root / BENCHMARK_REL)).replace("\\", "/")
        for path in (root / BENCHMARK_REL).rglob("*") if path.is_file()
    }
    if package_files != EXPECTED_PACKAGE_FILES:
        _fail("FPGA evidence package file set mismatch")
    if benchmark_files != EXPECTED_BENCHMARK_FILES:
        _fail("FPGA benchmark source file set mismatch")
    for relative, expected in FIXED_FILE_SHA256.items():
        path = root / relative
        if not path.is_file() or _sha256(path) != expected:
            _fail("fixed FPGA evidence hash mismatch for {}".format(relative))

    manifest = json.loads(_read_text(root / PACKAGE_REL / "manifest.json"))
    if manifest.get("classification") != "FPGA_DEBUGGER_TRANSCRIBED_SINGLE_RUN":
        _fail("FPGA evidence classification mismatch")
    if manifest.get("claim_status") != "partial":
        _fail("single-run claim must remain partial")
    if manifest.get("numeric_authority") != str(
            PACKAGE_REL / "raw_counters.csv").replace("\\", "/"):
        _fail("FPGA numeric authority mismatch")
    capture = manifest.get("capture", {})
    if capture != {
        "method": "operator-transcribed SDK debugger variables after report breakpoint",
        "record": "evidence/fpga_emulation/u5_sync_hp0_loopback/debugger_capture_transcript.txt",
        "retained_screenshot_or_memory_export": False,
        "correctness_gate": "passed_before_report_call",
        "debugger_intervention_in_measurement_window": False,
        "uart_tail_complete": False,
        "repeat_count": 1,
        "steady_state_captured": False,
    }:
        _fail("FPGA capture boundary mismatch")
    maturity = manifest.get("fpga_maturity", {})
    expected_dimensions = {
        "fpga_source_ready", "fpga_rtl_simulation", "fpga_synthesis",
        "fpga_implementation", "fpga_timing", "fpga_bitstream",
        "fpga_board_smoke", "fpga_workload_validation",
    }
    if set(maturity) != expected_dimensions:
        _fail("FPGA maturity dimensions are incomplete")
    if maturity.get("fpga_board_smoke") != "partial" or maturity.get(
            "fpga_workload_validation") != "partial":
        _fail("debugger-transcribed board maturity must remain partial")
    boundaries = manifest.get("boundaries", {})
    if not boundaries or any(boundaries.values()):
        _fail("FPGA nonclaim boundaries must all remain false")

    rows = _read_csv(root / PACKAGE_REL / "raw_counters.csv")
    if rows != [RAW_ROW]:
        _fail("raw FPGA counter row mismatch")
    calculated = derive_metrics(rows[0])
    derived_rows = _read_csv(root / PACKAGE_REL / "derived_metrics.csv")
    actual = {
        row["metric"]: (row["value"], row["unit"])
        for row in derived_rows
    }
    if len(actual) != len(derived_rows) or actual != DERIVED_VALUES:
        _fail("derived FPGA metric inventory mismatch")
    for metric, value in calculated.items():
        if actual[metric][0] != value:
            _fail("derived FPGA metric mismatch for {}".format(metric))

    artifact_rows = _read_csv(root / PACKAGE_REL / "artifacts.csv")
    artifacts = {row["artifact_id"]: row for row in artifact_rows}
    if len(artifacts) != len(artifact_rows):
        _fail("duplicate FPGA artifact identity")
    for artifact_id, (size, digest) in EXTERNAL_ARTIFACTS.items():
        row = artifacts.get(artifact_id)
        if not row or row.get("size_bytes") != size or row.get("sha256") != digest:
            _fail("FPGA artifact identity mismatch for {}".format(artifact_id))
    if artifacts["u5_bitstream"]["published_payload"] != "false" or artifacts[
            "u5_throughput_elf"]["published_payload"] != "false":
        _fail("bitstream and ELF must remain external")
    if artifacts["u5_reference_helloworld"]["published_payload"] != "true":
        _fail("reference SDK source must remain public")
    if artifacts["u5_debugger_transcript"]["published_payload"] != "true":
        _fail("debugger field transcript must remain public")

    source_text = _read_text(root / BENCHMARK_REL / "helloworld.c")
    _verify_source_control_flow(source_text)
    for relative in list(EXPECTED_PACKAGE_FILES) + list(EXPECTED_BENCHMARK_FILES):
        base = PACKAGE_REL if relative in EXPECTED_PACKAGE_FILES else BENCHMARK_REL
        path = root / base / relative
        if path.suffix.lower() in (".md", ".txt", ".json", ".csv", ".diff", ".c", ".h"):
            _verify_sensitive_text(path.relative_to(root), _read_text(path))

    _verify_docs(root, bram_claim_registered)
    if check_git_identity:
        _verify_git_source_tree(root)
    return "FPGA_EMULATION_EVIDENCE_PASS"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=Path(__file__).resolve().parents[2])
    args = parser.parse_args(argv)
    try:
        result = validate(args.root)
    except (EvidenceError, OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print("fpga-emulation-evidence: error: {}".format(error), file=sys.stderr)
        return 2
    print("fpga-emulation-evidence: {}".format(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
