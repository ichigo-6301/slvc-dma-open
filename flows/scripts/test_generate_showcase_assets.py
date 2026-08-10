#!/usr/bin/env python3
"""Fail-closed tests for deterministic DMA showcase assets and navigation."""

import json
from pathlib import Path
import re
import shutil
import struct
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zlib

from flows.scripts import check_showcase_render as render_check
from flows.scripts import generate_showcase_assets as generator


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]


class ShowcaseAssetsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        inputs = (
            generator.COMPARISONS_PATH,
            generator.CLAIMS_PATH,
            generator.C2B4_EVIDENCE_PATH,
            generator.CDC_EVIDENCE_PATH,
            generator.WRAPPER_PATH,
            generator.FRAME_WRAPPER_PATH,
            generator.RX_TOP_PATH,
            generator.C2B4_PROFILE_PATH,
            generator.GENERATOR_PATH,
            generator.README_PATH,
            generator.README_EN_PATH,
            generator.ARCHITECTURE_PATH,
            generator.ARCHITECTURE_EN_PATH,
            generator.RESEARCH_PATH,
            generator.RESEARCH_EN_PATH,
        ) + tuple(generator.BINARY_ASSETS)
        for relative in inputs:
            destination = self.root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(REPOSITORY_ROOT / relative, destination)
        generator.write(self.root)

    def tearDown(self):
        self.temp.cleanup()

    def replace_text(self, relative, old, new):
        path = self.root / relative
        text = path.read_text(encoding="utf-8")
        self.assertIn(old, text)
        path.write_text(text.replace(old, new, 1), encoding="utf-8")

    def reset_file(self, relative):
        shutil.copyfile(REPOSITORY_ROOT / relative, self.root / relative)

    def insert_png_chunk(self, relative, kind, data):
        path = self.root / relative
        payload = path.read_bytes()
        iend = payload.rfind(b"IEND") - 4
        self.assertGreaterEqual(iend, 8)
        raw_kind = kind.encode("ascii")
        crc = zlib.crc32(raw_kind)
        crc = zlib.crc32(data, crc) & 0xffffffff
        chunk = (
            struct.pack(">I", len(data)) + raw_kind + data +
            struct.pack(">I", crc)
        )
        path.write_bytes(payload[:iend] + chunk + payload[iend:])

    def test_tracked_assets_and_navigation_are_fresh(self):
        generator.check(REPOSITORY_ROOT)

    def test_generated_copy_passes_with_exact_metrics(self):
        metrics = generator.check(self.root)
        self.assertEqual(str(metrics["writer_total"]), "-7.97")
        self.assertEqual(str(metrics["writer_comb"]), "-15.84")
        self.assertEqual(metrics["wide_bytes"], 64)
        self.assertEqual(metrics["w_utilization"], 100)
        self.assertEqual(metrics["peak_outstanding"], 4)
        self.assertEqual((metrics["dc_mhz"], metrics["route_mhz"]), (550, 450))

    def test_repeated_generation_is_byte_identical(self):
        tracked = (
            generator.GENERATED_ASSETS + tuple(generator.BINARY_ASSETS) +
            (generator.ASSET_MANIFEST_PATH,)
        )
        before = {path: (self.root / path).read_bytes() for path in tracked}
        generator.write(self.root)
        after = {path: (self.root / path).read_bytes() for path in tracked}
        self.assertEqual(before, after)

    def test_writer_csv_delta_drift_fails(self):
        self.replace_text(generator.COMPARISONS_PATH, "-7.966353", "-7.900000")
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "formula mismatch"):
            generator.check(self.root)

    def test_writer_csv_formula_input_drift_fails(self):
        self.replace_text(generator.COMPARISONS_PATH, "7526.204", "7526.205")
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "formula mismatch"):
            generator.check(self.root)

    def test_required_claim_removal_fails(self):
        self.replace_text(
            generator.CLAIMS_PATH,
            "  - id: " + generator.THROUGHPUT_CLAIM,
            "  - id: removed_throughput_claim",
        )
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "missing required claim"):
            generator.check(self.root)

    def test_duplicate_claim_id_fails(self):
        path = self.root / generator.CLAIMS_PATH
        path.write_text(
            path.read_text(encoding="utf-8")
            + "\n  - id: {}\n    status: verified\n".format(generator.WRITER_CLAIM),
            encoding="utf-8",
        )
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "duplicate claim"):
            generator.check(self.root)

    def test_claim_scope_and_caveat_drift_fail(self):
        mutations = (
            (generator.WRITER_SCOPE["profile"], "complete_dma_profile"),
            (generator.WRITER_SCOPE["benchmark"], "complete DMA W0 versus W1"),
            (generator.THROUGHPUT_SCOPE["caveat"], "Measured board DDR throughput."),
            (generator.C2B4_SCOPE["source_ref"], "f" * 40),
        )
        for old, new in mutations:
            with self.subTest(new=new):
                self.reset_file(generator.CLAIMS_PATH)
                self.replace_text(generator.CLAIMS_PATH, old, new)
                with self.assertRaisesRegex(generator.ShowcaseAssetError, "scope identity"):
                    generator.check(self.root)

    def test_throughput_evidence_drift_fails(self):
        self.replace_text(generator.CDC_EVIDENCE_PATH, "bytes_per_cycle: 64", "bytes_per_cycle: 63")
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "throughput evidence mismatch"):
            generator.check(self.root)

    def test_c2b4_evidence_drift_fails(self):
        self.replace_text(generator.C2B4_EVIDENCE_PATH, "setup_wns_ns: 0.041322", "setup_wns_ns: 0.040000")
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "timing or area evidence mismatch"):
            generator.check(self.root)

    def test_rtl_and_profile_identity_drift_fail(self):
        mutations = (
            (generator.RX_TOP_PATH, "dma_rx_payload_cdc_bridge", "removed_cdc_bridge"),
            (generator.C2B4_PROFILE_PATH, "memory_axi_width: 512", "memory_axi_width: 256"),
        )
        for path, old, new in mutations:
            with self.subTest(path=path):
                self.reset_file(path)
                self.replace_text(path, old, new)
                with self.assertRaisesRegex(generator.ShowcaseAssetError, "architecture token"):
                    generator.check(self.root)

    def test_generated_svg_tamper_fails(self):
        path = self.root / generator.PPA_ASSET
        path.write_bytes(path.read_bytes() + b"<!-- tampered -->\n")
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "stale showcase assets"):
            generator.check(self.root)

    def test_manifest_tamper_fails(self):
        path = self.root / generator.ASSET_MANIFEST_PATH
        data = json.loads(path.read_text(encoding="utf-8"))
        data["assets"][-1]["sha256"] = "0" * 64
        path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "manifest is stale"):
            generator.check(self.root)

    def test_obsolete_asset_reappearance_fails(self):
        path = self.root / generator.OBSOLETE_ASSETS[0]
        path.write_text("obsolete\n", encoding="utf-8")
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "stale showcase assets"):
            generator.check(self.root)

    def validate_mutated_svg(self, relative):
        generator._validate_svg(
            relative,
            (self.root / relative).read_bytes(),
            generator.GENERATED_RULES[relative.name],
        )

    def test_generated_svg_external_resource_fails(self):
        path = generator.OVERVIEW_ASSET
        self.replace_text(path, "</svg>", '<image href="https://example.com/x.png"/></svg>')
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "forbidden SVG content"):
            self.validate_mutated_svg(path)

    def test_generated_svg_private_path_fails(self):
        path = generator.OVERVIEW_ASSET
        self.replace_text(path, "</svg>", "<text>C:\\private\\asset</text></svg>")
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "forbidden SVG content"):
            self.validate_mutated_svg(path)

    def test_generated_svg_gradient_fails(self):
        path = generator.OVERVIEW_ASSET
        self.replace_text(path, "</svg>", '<linearGradient id="g"/></svg>')
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "forbidden SVG content"):
            self.validate_mutated_svg(path)

    def test_readme_asset_reference_deletion_fails(self):
        self.replace_text(
            generator.README_PATH,
            'href="{}"'.format(generator.WRITER_CDC_PNG.as_posix()),
            'href="docs/assets/missing.svg"',
        )
        with self.assertRaisesRegex(
                generator.ShowcaseAssetError, "href/src identity mismatch"):
            generator.check(self.root)

    def test_readme_anchor_deletion_fails(self):
        self.replace_text(
            generator.README_EN_PATH,
            '<a id="memory-profiles-and-cdc"></a>',
            '<a id="memory-profiles-and-cdc-removed"></a>',
        )
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "must contain anchor"):
            generator.check(self.root)

    def test_readme_claim_marker_mismatch_fails(self):
        self.replace_text(
            generator.README_EN_PATH,
            generator.WRITER_CLAIM,
            "wrong_writer_claim",
        )
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "claim marker parity"):
            generator.check(self.root)

    def test_research_commit_drift_fails(self):
        self.replace_text(generator.RESEARCH_PATH, generator.RESEARCH_COMMIT, "0" * 40)
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "fixed-commit identity"):
            generator.check(self.root)

    def test_research_archive_tag_drift_fails(self):
        self.replace_text(
            generator.RESEARCH_EN_PATH,
            generator.RESEARCH_ARCHIVE_TAG,
            "archive/wrong-storage-clock-gating-snapshot",
        )
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "archive tag"):
            generator.check(self.root)

    def test_deleted_research_branch_link_fails(self):
        path = self.root / generator.README_EN_PATH
        path.write_text(
            path.read_text(encoding="utf-8")
            + "\nhttps://github.com/ichigo-6301/slvc-dma-open/tree/"
            + generator.LEGACY_RESEARCH_BRANCH
            + "\n",
            encoding="utf-8",
        )
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "deleted research branch"):
            generator.check(self.root)

    def test_research_power_metric_injection_fails(self):
        path = self.root / generator.RESEARCH_EN_PATH
        path.write_text(path.read_text(encoding="utf-8") + "\nBursty: -87.91%\n", encoding="utf-8")
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "must not publish"):
            generator.check(self.root)

    def test_binary_01_fixed_identity_and_metadata_free_chunks(self):
        for relative, expected in generator.BINARY_ASSETS.items():
            with self.subTest(asset=relative):
                actual = generator._png_identity(self.root / relative)
                for field in ("sha256", "size_bytes", "width", "height"):
                    self.assertEqual(actual[field], expected[field])
                self.assertEqual(actual["chunks"][0], "IHDR")
                self.assertEqual(actual["chunks"][-1], "IEND")
                self.assertEqual(set(actual["chunks"]), {"IHDR", "IDAT", "IEND"})

    def test_binary_02_missing_or_payload_tamper_fails(self):
        relative = generator.SYSTEM_OVERVIEW_PNG
        path = self.root / relative
        path.unlink()
        with self.assertRaisesRegex(
                generator.ShowcaseAssetError, "missing binary showcase asset"):
            generator.check(self.root)
        self.reset_file(relative)
        payload = bytearray(path.read_bytes())
        idat_data = payload.index(b"IDAT") + 4
        payload[idat_data] ^= 0x01
        path.write_bytes(payload)
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "CRC mismatch"):
            generator.check(self.root)

    def test_binary_03_metadata_chunks_and_trailing_data_fail(self):
        relative = generator.WRITER_CDC_PNG
        mutations = (
            ("caBX", b"content-credentials"),
            ("tEXt", b"Software\x00private-tool"),
            ("eXIf", b"II*\x00"),
        )
        for kind, data in mutations:
            with self.subTest(chunk=kind):
                self.reset_file(relative)
                self.insert_png_chunk(relative, kind, data)
                with self.assertRaisesRegex(
                        generator.ShowcaseAssetError, "forbidden metadata"):
                    generator.check(self.root)
        self.reset_file(relative)
        path = self.root / relative
        path.write_bytes(path.read_bytes() + b"private-path")
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "trailing data"):
            generator.check(self.root)

    def test_binary_04_manifest_scope_and_authority_are_fixed(self):
        path = self.root / generator.ASSET_MANIFEST_PATH
        manifest = json.loads(path.read_text(encoding="ascii"))
        self.assertEqual(manifest["schema_version"], "1.1.0")
        entries = {item["path"]: item for item in manifest["assets"]}
        for relative, expected in generator.BINARY_ASSETS.items():
            entry = entries[relative.as_posix()]
            self.assertEqual(entry["source_type"], "authored_binary_showcase")
            self.assertIs(entry["numeric_authority"], False)
            self.assertEqual(entry["claim_ids"], [])
            self.assertEqual(entry["role"], expected["role"])
        original = path.read_bytes()
        mutations = (
            ("numeric_authority", True),
            ("claim_ids", [generator.WRITER_CLAIM]),
            ("source_type", "verified_numeric_evidence"),
            ("role", "complete_dma_ppa"),
        )
        for field, value in mutations:
            with self.subTest(field=field):
                path.write_bytes(original)
                changed = json.loads(path.read_text(encoding="ascii"))
                changed["assets"][-1][field] = value
                path.write_text(json.dumps(changed, indent=2) + "\n", encoding="ascii")
                with self.assertRaisesRegex(
                        generator.ShowcaseAssetError, "manifest is stale"):
                    generator.check(self.root)

    def test_homepage_01_exact_three_image_order_and_alt_contract(self):
        pattern = re.compile(
            r'<p align="center">\s*<a href="([^"]+)">\s*'
            r'<img src="([^"]+)"\s+width="([^"]+)"\s+alt="([^"]+)">\s*'
            r'</a>\s*</p>', re.MULTILINE,
        )
        expected = [item.as_posix() for item in generator.README_ASSET_ORDER]
        for readme in (generator.README_PATH, generator.README_EN_PATH):
            text = (self.root / readme).read_text(encoding="utf-8")
            blocks = [match.groups() for match in pattern.finditer(text)]
            self.assertEqual([item[0] for item in blocks], expected)
            self.assertEqual([item[1] for item in blocks], expected)
            self.assertEqual([item[2] for item in blocks], ["1000"] * 3)
            self.assertEqual(
                [item[3] for item in blocks],
                [generator.README_ASSET_ALTS[item]
                 for item in generator.README_ASSET_ORDER],
            )

    def test_homepage_02_old_svg_extra_width_and_href_mutations_fail(self):
        path = self.root / generator.README_PATH
        original = path.read_text(encoding="utf-8")
        mutations = (
            original + (
                '\n<p align="center"><a href="{0}"><img src="{0}" '
                'width="1000" alt="old"></a></p>\n'
            ).format(generator.FRAME_LIFECYCLE_ASSET.as_posix()),
            original.replace('width="1000"', 'width="999"', 1),
            original.replace(
                'href="{}"'.format(generator.SYSTEM_OVERVIEW_PNG.as_posix()),
                'href="docs/assets/showcase/mismatch.png"', 1,
            ),
        )
        for index, changed in enumerate(mutations):
            with self.subTest(mutation=index):
                path.write_text(changed, encoding="utf-8")
                with self.assertRaisesRegex(
                        generator.ShowcaseAssetError,
                        "exactly three|width must be 1000|href/src identity"):
                    generator.check(self.root)
        path.write_text(original, encoding="utf-8")

    def test_homepage_03_detailed_assets_are_bilingual_and_off_homepage(self):
        for readme in (generator.README_PATH, generator.README_EN_PATH):
            text = (self.root / readme).read_text(encoding="utf-8")
            for asset in generator.README_DETAILED_ASSETS:
                self.assertEqual(text.count("({})".format(asset.as_posix())), 1)
                self.assertNotRegex(
                    text, r'<img[^>]+src="{}"'.format(re.escape(asset.as_posix()))
                )
        for document in (
                generator.ARCHITECTURE_PATH,
                generator.ARCHITECTURE_EN_PATH):
            text = (self.root / document).read_text(encoding="utf-8")
            for asset in generator.ARCHITECTURE_ASSETS:
                self.assertEqual(text.count(asset.name), 1)

    def test_homepage_04_binary_claim_and_research_metric_registration_fail(self):
        claims = self.root / generator.CLAIMS_PATH
        claims.write_text(
            claims.read_text(encoding="utf-8") +
            "\nasset: {}\n".format(generator.SYSTEM_OVERVIEW_PNG.as_posix()),
            encoding="utf-8",
        )
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "must not reference"):
            generator.check(self.root)
        self.reset_file(generator.CLAIMS_PATH)
        readme = self.root / generator.README_EN_PATH
        readme.write_text(
            readme.read_text(encoding="utf-8") + "\nBursty dynamic: -87.91\n",
            encoding="utf-8",
        )
        with self.assertRaisesRegex(generator.ShowcaseAssetError, "branch-only power metric"):
            generator.check(self.root)

    def test_homepage_05_real_browser_desktop_mobile_light_dark(self):
        browser, reports = render_check.check_homepage_render(self.root)
        self.assertTrue(browser.is_file())
        self.assertEqual(set(reports), {
            "desktop-light", "desktop-dark", "mobile-light", "mobile-dark",
        })
        for report in reports.values():
            self.assertEqual(report["failures"], [])
            self.assertEqual(report["image_count"], 3)
            self.assertGreater(report["png_bytes"], 2000)

    def test_visual_01_exact_canvas_and_theme_contract(self):
        for relative in generator.GENERATED_ASSETS:
            with self.subTest(asset=relative.name):
                text = (self.root / relative).read_text(encoding="ascii")
                root = ET.fromstring(text)
                self.assertEqual(root.attrib["width"], "1600")
                self.assertEqual(root.attrib["height"], "1000")
                self.assertEqual(root.attrib["viewBox"], "0 0 1600 1000")
                self.assertEqual(
                    root.attrib["preserveAspectRatio"], "xMidYMid meet"
                )
                for token in generator.THEME_TOKENS:
                    self.assertIn(token, text)

    def test_visual_02_banned_palette_and_rounded_box_mutations_fail(self):
        path = generator.VIRTUAL_CHANNEL_ASSET
        original = (self.root / path).read_text(encoding="ascii")
        for mutation in ('#dbeafe', '#f0fdf4', 'rx="8"'):
            with self.subTest(mutation=mutation):
                if mutation.startswith("#"):
                    changed = original.replace("#ffffff", mutation, 1)
                else:
                    changed = original.replace('<rect ', '<rect {} '.format(mutation), 1)
                (self.root / path).write_text(changed, encoding="ascii")
                with self.assertRaisesRegex(
                        generator.ShowcaseAssetError,
                        "forbidden pastel|rounded box"):
                    self.validate_mutated_svg(path)
        (self.root / path).write_text(original, encoding="ascii")

    def test_visual_03_forbidden_svg_feature_mutations_fail(self):
        path = generator.OVERVIEW_ASSET
        original = (self.root / path).read_text(encoding="ascii")
        mutations = (
            '<filter id="shadow"/>',
            '<image href="data:image/png;base64,AAAA"/>',
            '<style>@font-face{font-family:private}</style>',
            '<foreignObject/>',
        )
        for mutation in mutations:
            with self.subTest(mutation=mutation):
                changed = original.replace("</svg>", mutation + "</svg>")
                (self.root / path).write_text(changed, encoding="ascii")
                with self.assertRaisesRegex(
                        generator.ShowcaseAssetError, "forbidden SVG content"):
                    self.validate_mutated_svg(path)
        (self.root / path).write_text(original, encoding="ascii")

    def test_visual_04_readmes_embed_exact_three_clickable_assets(self):
        for readme in (generator.README_PATH, generator.README_EN_PATH):
            text = (self.root / readme).read_text(encoding="utf-8")
            positions = []
            for asset in generator.README_ASSET_ORDER:
                pattern = re.compile(
                    r'<p align="center">\s*<a href="{0}">\s*'
                    r'<img src="{0}"\s+width="1000"\s+alt="[^"]+">\s*'
                    r'</a>\s*</p>'.format(re.escape(asset.as_posix())),
                    re.MULTILINE,
                )
                matches = list(pattern.finditer(text))
                self.assertEqual(len(matches), 1, (readme, asset))
                positions.append(matches[0].start())
            self.assertEqual(positions, sorted(positions))

    def test_visual_05_lifecycle_requires_header_and_payload_at_gate(self):
        root = ET.fromstring(
            (self.root / generator.FRAME_LIFECYCLE_ASSET).read_bytes()
        )
        by_id = {
            element.attrib["id"]: element
            for element in root.iter() if "id" in element.attrib
        }
        self.assertEqual(
            by_id["admission-gate"].attrib["data-requires"],
            "header-control,payload",
        )
        self.assertEqual(
            by_id["control-to-admission"].attrib["data-connects"],
            "header-control-to-admission",
        )
        self.assertEqual(
            by_id["payload-to-admission"].attrib["data-connects"],
            "payload-to-admission",
        )

    def test_visual_06_lifecycle_commit_completion_release_order(self):
        root = ET.fromstring(
            (self.root / generator.FRAME_LIFECYCLE_ASSET).read_bytes()
        )
        by_id = {
            element.attrib["id"]: element
            for element in root.iter() if "id" in element.attrib
        }
        self.assertEqual(by_id["commit-boundary"].attrib["data-boundary-order"], "1")
        self.assertEqual(by_id["release-boundary"].attrib["data-boundary-order"], "2")
        completion = [
            int(by_id[name].attrib["data-completion-order"])
            for name in ("cqe-body", "owner-valid", "release-frame-ownership")
        ]
        self.assertEqual(completion, [1, 2, 3])
        control = [
            int(by_id[name].attrib["data-control-order"])
            for name in (
                "header-beat", "parse-crc", "match-context",
                "check-resources", "reserve-reject",
            )
        ]
        self.assertEqual(control, [1, 2, 3, 4, 5])
        for edge in (
                "header-to-parse", "parse-to-match", "match-to-check",
                "check-to-reserve"):
            self.assertEqual(by_id[edge].attrib["class"], "flow")

    def test_visual_07_async_transaction_directions_are_explicit(self):
        root = ET.fromstring(
            (self.root / generator.MEMORY_PROFILES_ASSET).read_bytes()
        )
        by_id = {
            element.attrib["id"]: element
            for element in root.iter() if "id" in element.attrib
        }
        expected = {
            "command": "aclk-to-mem-clk",
            "payload": "aclk-to-mem-clk",
            "completion": "mem-clk-to-aclk",
        }
        for profile in ("async64", "async512"):
            for suffix, direction in expected.items():
                edge = by_id["{}-{}".format(profile, suffix)]
                self.assertEqual(edge.attrib["data-direction"], direction)
                self.assertIn(edge.attrib.get("class"), ("flow-blue", "flow-return"))
                if direction == "aclk-to-mem-clk":
                    self.assertTrue(edge.attrib["d"].startswith("M570"))
                else:
                    self.assertTrue(edge.attrib["d"].startswith("M940"))

    def test_visual_08_profile_serializer_bypass_and_axi_domain(self):
        root = ET.fromstring(
            (self.root / generator.MEMORY_PROFILES_ASSET).read_bytes()
        )
        by_id = {
            element.attrib["id"]: element
            for element in root.iter() if "id" in element.attrib
        }
        same = by_id["profile-same-clock512"]
        async64 = by_id["profile-async64"]
        async512 = by_id["profile-async512"]
        self.assertEqual(same.attrib["data-cdc"], "bypass")
        self.assertIn("512-to-64 serializer", "".join(async64.itertext()))
        self.assertNotIn("serializer", "".join(async512.itertext()).lower())
        self.assertNotIn("AW / W / B", "".join(same.itertext()))
        self.assertIn("AW / W / B", "".join(async64.itertext()))
        self.assertIn("AW / W / B", "".join(async512.itertext()))

    def test_visual_09_virtual_channel_semantics_and_caveat(self):
        text = (self.root / generator.VIRTUAL_CHANNEL_ASSET).read_text(
            encoding="ascii"
        )
        for token in (
                "dedicated capacity", "free-list capacity",
                "Only committed frames are visible", "Selector locks one frame",
                "no source interleave", "channel 0 full",
                "channel 1 progresses"):
            self.assertIn(token, text)

    def test_visual_10_ppa_values_remain_evidence_bound(self):
        metrics = generator._extract_metrics(self.root)
        text = (self.root / generator.PPA_ASSET).read_text(encoding="ascii")
        expected = (
            "{}%".format(metrics["writer_total"]),
            "{}%".format(metrics["writer_comb"]),
            "{} B/cycle".format(metrics["wide_bytes"]),
            "{} B/cycle".format(metrics["async64_bytes"]),
            "+{} / +{} ns".format(metrics["setup_wns"], metrics["hold_wns"]),
            "{} mm2".format(metrics["area_mm2"]),
        )
        for token in expected:
            self.assertIn(token, text)
        self.assertIn(
            "Three independent evidence scopes; not one complete-DMA PPA result.",
            text,
        )

    def test_visual_11_all_five_regenerate_byte_identically(self):
        before = {
            path: (self.root / path).read_bytes()
            for path in generator.GENERATED_ASSETS
        }
        generator.write(self.root)
        after = {
            path: (self.root / path).read_bytes()
            for path in generator.GENERATED_ASSETS
        }
        self.assertEqual(before, after)

    def test_visual_12_real_browser_previews_have_clean_layout(self):
        browser, reports = render_check.check_render(self.root)
        self.assertTrue(browser.is_file())
        self.assertEqual(set(reports), {
            path.as_posix() for path in generator.GENERATED_ASSETS
        })
        for report in reports.values():
            self.assertEqual(report["failures"], [])
            self.assertEqual(report["rendered_width"], 1000)
            self.assertEqual(report["rendered_height"], 625)
            self.assertGreater(report["png_bytes"], 2000)


if __name__ == "__main__":
    unittest.main()
