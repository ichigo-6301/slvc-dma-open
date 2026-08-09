#!/usr/bin/env python3
"""Render SLVC DMA showcase SVGs in a real browser and fail on layout drift."""

from __future__ import print_function

import argparse
import html
import json
import os
from pathlib import Path
import platform
import re
import shutil
import struct
import subprocess
import sys
import tempfile

try:
    from flows.scripts import generate_showcase_assets as generator
except ModuleNotFoundError:
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
    from flows.scripts import generate_showcase_assets as generator


RESULT_PATTERN = re.compile(
    r'<pre id="showcase-render-result">(.*?)</pre>', re.DOTALL
)


class ShowcaseRenderError(RuntimeError):
    pass


def _candidate_paths():
    override = os.environ.get("SHOWCASE_BROWSER")
    if override:
        yield Path(override)
        return
    for name in (
            "google-chrome", "google-chrome-stable", "chromium",
            "chromium-browser", "chrome", "msedge"):
        resolved = shutil.which(name)
        if resolved:
            yield Path(resolved)
    roots = tuple(
        Path(value) for value in (
            os.environ.get("PROGRAMFILES"),
            os.environ.get("PROGRAMFILES(X86)"),
            os.environ.get("LOCALAPPDATA"),
        ) if value
    )
    suffixes = (
        Path("Google/Chrome/Application/chrome.exe"),
        Path("Microsoft/Edge/Application/msedge.exe"),
    )
    for root in roots:
        for suffix in suffixes:
            yield root / suffix
    if sys.platform.startswith("linux") and "microsoft" in platform.release().lower():
        yield Path("/mnt/c/Program Files/Google/Chrome/Application/chrome.exe")
        yield Path("/mnt/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe")


def discover_browser():
    seen = set()
    for candidate in _candidate_paths():
        normalized = str(candidate.resolve()) if candidate.exists() else str(candidate)
        if normalized in seen:
            continue
        seen.add(normalized)
        if candidate.is_file():
            return candidate.resolve()
    override = os.environ.get("SHOWCASE_BROWSER")
    if override:
        raise ShowcaseRenderError(
            "SHOWCASE_BROWSER does not name an executable file: {}".format(override)
        )
    raise ShowcaseRenderError(
        "Chrome, Chromium, or Edge is required for showcase render checks"
    )


def _html_document(svg_text):
    script = r"""
(() => {
  const failures = [];
  const svg = document.querySelector('svg');
  const tolerance = 1.5;
  const rounded = value => Math.round(value * 100) / 100;
  const record = (code, detail) => failures.push(code + ': ' + detail);
  const bounds = element => {
    const box = element.getBBox();
    return {x: box.x, y: box.y, width: box.width, height: box.height,
            right: box.x + box.width, bottom: box.y + box.height};
  };
  if (!svg) {
    record('missing-svg', 'inline SVG was not parsed');
  } else {
    const view = svg.viewBox.baseVal;
    const texts = Array.from(svg.querySelectorAll('text'));
    for (const node of texts) {
      const box = bounds(node);
      const size = parseFloat(getComputedStyle(node).fontSize || '0');
      const label = (node.textContent || '').trim();
      if (!Number.isFinite(size) || size < 16) {
        record('font-size', label + ' = ' + size);
      }
      if (box.x < view.x - tolerance || box.y < view.y - tolerance ||
          box.right > view.x + view.width + tolerance ||
          box.bottom > view.y + view.height + tolerance) {
        record('canvas-overflow', label + ' @ ' + JSON.stringify(box));
      }
      const region = node.closest('[data-layout-region]');
      if (!region) {
        record('missing-region', label);
        continue;
      }
      const layoutBox = Array.from(region.children).find(
        child => child.hasAttribute && child.hasAttribute('data-layout-box')
      );
      if (!layoutBox) {
        record('missing-layout-box', region.getAttribute('data-layout-region'));
        continue;
      }
      const limit = bounds(layoutBox);
      if (box.x < limit.x - tolerance || box.y < limit.y - tolerance ||
          box.right > limit.right + tolerance || box.bottom > limit.bottom + tolerance) {
        record('region-overflow', label + ' in ' +
          region.getAttribute('data-layout-region') + ' @ ' + JSON.stringify(box));
      }
    }
    for (const region of svg.querySelectorAll('[data-layout-region]')) {
      const directTexts = Array.from(region.querySelectorAll('text')).filter(
        node => node.closest('[data-layout-region]') === region &&
                !node.hasAttribute('data-overlap-ok')
      );
      const boxes = directTexts.map(node => ({node, box: bounds(node)}));
      for (let i = 0; i < boxes.length; i += 1) {
        for (let j = i + 1; j < boxes.length; j += 1) {
          const a = boxes[i].box;
          const b = boxes[j].box;
          const overlapX = Math.min(a.right, b.right) - Math.max(a.x, b.x);
          const overlapY = Math.min(a.bottom, b.bottom) - Math.max(a.y, b.y);
          if (overlapX > tolerance && overlapY > tolerance) {
            record('text-overlap',
              region.getAttribute('data-layout-region') + ': ' +
              boxes[i].node.textContent.trim() + ' / ' +
              boxes[j].node.textContent.trim());
          }
        }
      }
    }
  }
  const output = {
    failures,
    text_count: svg ? svg.querySelectorAll('text').length : 0,
    region_count: svg ? svg.querySelectorAll('[data-layout-region]').length : 0,
    rendered_width: svg ? rounded(svg.getBoundingClientRect().width) : 0,
    rendered_height: svg ? rounded(svg.getBoundingClientRect().height) : 0
  };
  document.getElementById('showcase-render-result').textContent = JSON.stringify(output);
})();
"""
    return """<!doctype html>
<html><head><meta charset="utf-8"><style>
html,body{{margin:0;width:1000px;height:625px;overflow:hidden;background:#ffffff}}
svg{{display:block;width:1000px;height:625px}}
#showcase-render-result{{display:none}}
</style></head><body>
{svg}
<pre id="showcase-render-result">pending</pre>
<script>{script}</script>
</body></html>
""".format(svg=svg_text, script=script)


def _uses_wsl_windows_browser(browser):
    return (
        sys.platform.startswith("linux") and
        "microsoft" in platform.release().lower() and
        browser.suffix.lower() == ".exe"
    )


def _windows_path(path):
    completed = subprocess.run(
        ("wslpath", "-w", str(path)),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        universal_newlines=True,
        timeout=10,
    )
    if completed.returncode != 0 or not completed.stdout.strip():
        raise ShowcaseRenderError(
            "failed to translate WSL path for Windows browser: {}".format(path)
        )
    return completed.stdout.strip()


def _windows_file_uri(path):
    translated = _windows_path(path).replace("\\", "/").replace(" ", "%20")
    return "file:///" + translated


def _browser_command(browser, profile, extra, page):
    interop = _uses_wsl_windows_browser(browser)
    profile_text = _windows_path(profile) if interop else str(profile)
    translated_extra = []
    for item in extra:
        if interop and item.startswith("--screenshot="):
            item = "--screenshot={}".format(
                _windows_path(Path(item.split("=", 1)[1]))
            )
        translated_extra.append(item)
    page_uri = _windows_file_uri(page) if interop else page.as_uri()
    return [
        str(browser),
        "--headless=new",
        "--disable-gpu",
        "--disable-dev-shm-usage",
        "--hide-scrollbars",
        "--no-sandbox",
        "--allow-file-access-from-files",
        "--force-device-scale-factor=1",
        "--window-size=1000,625",
        "--user-data-dir={}".format(profile_text),
    ] + translated_extra + [page_uri]


def _run_browser(command):
    completed = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        universal_newlines=True,
        timeout=45,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip().splitlines()
        raise ShowcaseRenderError(
            "browser exited {}: {}".format(
                completed.returncode,
                detail[-1] if detail else "no diagnostic",
            )
        )
    return completed.stdout


def _png_dimensions(path):
    payload = path.read_bytes()
    if len(payload) < 24 or payload[:8] != b"\x89PNG\r\n\x1a\n":
        raise ShowcaseRenderError("browser did not produce a valid PNG: {}".format(path))
    width, height = struct.unpack(">II", payload[16:24])
    if (width, height) != (1000, 625):
        raise ShowcaseRenderError(
            "preview dimensions mismatch for {}: {}x{}".format(path, width, height)
        )
    if len(payload) < 2000:
        raise ShowcaseRenderError("preview is unexpectedly small or blank: {}".format(path))
    return len(payload)


def check_render(root, assets=None, browser=None):
    root = Path(root).resolve()
    browser = Path(browser).resolve() if browser else discover_browser()
    selected = tuple(assets or generator.GENERATED_ASSETS)
    reports = {}
    temporary_parent = None
    if _uses_wsl_windows_browser(browser):
        temporary_parent = root / "build"
        temporary_parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
            prefix="slvc-dma-showcase-render-",
            dir=str(temporary_parent) if temporary_parent else None) as temporary:
        temporary_root = Path(temporary)
        for index, relative in enumerate(selected):
            svg_path = root / relative
            if not svg_path.is_file():
                raise ShowcaseRenderError("missing showcase SVG: {}".format(relative))
            try:
                svg_text = svg_path.read_text(encoding="ascii")
            except UnicodeDecodeError as error:
                raise ShowcaseRenderError("non-ASCII SVG {}: {}".format(relative, error))
            html_path = temporary_root / (relative.stem + ".html")
            png_path = temporary_root / (relative.stem + ".png")
            html_path.write_text(_html_document(svg_text), encoding="utf-8")
            dump_profile = temporary_root / "profile-dump-{}".format(index)
            dumped = _run_browser(_browser_command(
                browser,
                dump_profile,
                ("--dump-dom", "--virtual-time-budget=1000"),
                html_path,
            ))
            match = RESULT_PATTERN.search(dumped)
            if not match:
                raise ShowcaseRenderError(
                    "browser layout result missing for {}".format(relative)
                )
            try:
                report = json.loads(html.unescape(match.group(1)))
            except (TypeError, ValueError) as error:
                raise ShowcaseRenderError(
                    "invalid browser layout result for {}: {}".format(relative, error)
                )
            if report.get("rendered_width") != 1000 or report.get("rendered_height") != 625:
                raise ShowcaseRenderError(
                    "rendered SVG size mismatch for {}: {}".format(relative, report)
                )
            if report.get("text_count", 0) < 1 or report.get("region_count", 0) < 1:
                raise ShowcaseRenderError(
                    "empty browser layout report for {}: {}".format(relative, report)
                )
            if report.get("failures"):
                raise ShowcaseRenderError(
                    "layout failure for {}: {}".format(
                        relative, "; ".join(report["failures"])
                    )
                )
            shot_profile = temporary_root / "profile-shot-{}".format(index)
            _run_browser(_browser_command(
                browser,
                shot_profile,
                (
                    "--run-all-compositor-stages-before-draw",
                    "--screenshot={}".format(png_path),
                ),
                html_path,
            ))
            report["png_bytes"] = _png_dimensions(png_path)
            reports[relative.as_posix()] = report
    return browser, reports


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=Path(__file__).resolve().parents[2])
    parser.add_argument("--browser")
    args = parser.parse_args(argv)
    try:
        browser, reports = check_render(args.root, browser=args.browser)
    except (OSError, subprocess.SubprocessError, ShowcaseRenderError) as error:
        print("showcase-render: error: {}".format(error), file=sys.stderr)
        return 2
    print(
        "SHOWCASE_RENDER_PASS browser={} assets={} texts={} regions={}".format(
            browser,
            len(reports),
            sum(item["text_count"] for item in reports.values()),
            sum(item["region_count"] for item in reports.values()),
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
