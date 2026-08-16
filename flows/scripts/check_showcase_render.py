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


def _browser_command(browser, profile, extra, page, width=1000, height=625):
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
        "--window-size={},{}".format(width, height),
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


def _png_dimensions(path, expected=(1000, 625)):
    payload = path.read_bytes()
    if len(payload) < 24 or payload[:8] != b"\x89PNG\r\n\x1a\n":
        raise ShowcaseRenderError("browser did not produce a valid PNG: {}".format(path))
    width, height = struct.unpack(">II", payload[16:24])
    if (width, height) != expected:
        raise ShowcaseRenderError(
            "preview dimensions mismatch for {}: {}x{}".format(path, width, height)
        )
    if len(payload) < 2000:
        raise ShowcaseRenderError("preview is unexpectedly small or blank: {}".format(path))
    return len(payload)


def _asset_uri(path, browser):
    if _uses_wsl_windows_browser(browser):
        return _windows_file_uri(path)
    return path.resolve().as_uri()


def _homepage_document(root, browser, dark):
    assets = []
    expected_dimensions = {
        generator.SYSTEM_OVERVIEW_PNG: (1586, 992),
        generator.WRITER_CDC_PNG: (1586, 992),
        generator.PPA_ASSET: (1600, 1000),
    }
    blocks = []
    for relative in generator.README_ASSET_ORDER:
        uri = _asset_uri(root / relative, browser)
        width, height = expected_dimensions[relative]
        assets.append({
            "path": relative.as_posix(),
            "uri": uri,
            "width": width,
            "height": height,
        })
        blocks.append(
            '<p align="center"><a href="{uri}"><img src="{uri}" '
            'width="1000" alt="{alt}"></a></p>'.format(
                uri=html.escape(uri, quote=True),
                alt=html.escape(generator.README_ASSET_ALTS[relative], quote=True),
            )
        )
    script = r"""
(() => {
  const evaluate = () => {
  const failures = [];
  const expected = EXPECTED_ASSETS;
  const images = Array.from(document.querySelectorAll('main img'));
  const record = (code, detail) => failures.push(code + ': ' + detail);
  if (images.length !== expected.length) {
    record('image-count', images.length + ' != ' + expected.length);
  }
  if (document.documentElement.scrollWidth > document.documentElement.clientWidth + 1) {
    record('horizontal-scroll', document.documentElement.scrollWidth + ' > ' +
      document.documentElement.clientWidth);
  }
  const margins = [];
  const rendered = [];
  images.forEach((image, index) => {
    const identity = expected[index];
    const rect = image.getBoundingClientRect();
    const anchor = image.closest('a');
    const paragraph = image.closest('p');
    if (!image.complete || image.naturalWidth === 0) {
      record('not-loaded', identity.path);
    }
    if (image.naturalWidth !== identity.width || image.naturalHeight !== identity.height) {
      record('natural-size', identity.path + ': ' + image.naturalWidth + 'x' +
        image.naturalHeight);
    }
    if (image.getAttribute('width') !== '1000') {
      record('width-contract', identity.path);
    }
    if (!anchor || anchor.getAttribute('href') !== image.getAttribute('src')) {
      record('click-target', identity.path);
    }
    if (rect.left < -1 || rect.right > window.innerWidth + 1 || rect.width <= 0 ||
        rect.height <= 0) {
      record('viewport-overflow', identity.path + ': ' + JSON.stringify({
        left: rect.left, right: rect.right, width: rect.width, height: rect.height
      }));
    }
    if (window.innerWidth >= 1040 && Math.abs(rect.width - 1000) > 1) {
      record('desktop-width', identity.path + ': ' + rect.width);
    }
    if (paragraph) {
      const style = getComputedStyle(paragraph);
      margins.push(style.marginTop + '/' + style.marginBottom);
    }
    rendered.push({path: identity.path, width: rect.width, height: rect.height});
  });
  if (new Set(margins).size > 1) {
    record('spacing', JSON.stringify(margins));
  }
  const output = {
    failures,
    image_count: images.length,
    viewport_width: window.innerWidth,
    viewport_height: window.innerHeight,
    page_scroll_width: document.documentElement.scrollWidth,
    rendered
  };
  document.getElementById('showcase-render-result').textContent = JSON.stringify(output);
  };
  if (document.readyState === 'complete') {
    evaluate();
  } else {
    window.addEventListener('load', evaluate, {once: true});
  }
})();
""".replace("EXPECTED_ASSETS", json.dumps(assets, separators=(",", ":")))
    background = "#0d1117" if dark else "#ffffff"
    return """<!doctype html>
<html><head><meta charset="utf-8"><style>
html,body{{margin:0;min-width:0;background:{background};}}
body{{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;}}
main{{box-sizing:border-box;width:100%;max-width:1040px;margin:0 auto;padding:20px;}}
p{{margin:24px 0;}}
a{{display:block;}}
img{{box-sizing:border-box;display:block;width:1000px;max-width:100%;height:auto;
     margin:0 auto;background:#ffffff;}}
@media (max-width:600px){{main{{padding:16px;}}}}
#showcase-render-result{{display:none}}
</style></head><body>
<main>{blocks}</main>
<pre id="showcase-render-result">pending</pre>
<script>{script}</script>
</body></html>
""".format(
        background=background,
        blocks="\n".join(blocks),
        script=script,
    )


def check_homepage_render(root, browser=None):
    root = Path(root).resolve()
    browser = Path(browser).resolve() if browser else discover_browser()
    cases = (
        ("desktop-light", 1200, 900, False),
        ("desktop-dark", 1200, 900, True),
        ("mobile-light", 390, 844, False),
        ("mobile-dark", 390, 844, True),
    )
    reports = {}
    temporary_parent = None
    if _uses_wsl_windows_browser(browser):
        temporary_parent = root / "build"
        temporary_parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
            prefix="slvc-dma-homepage-render-",
            dir=str(temporary_parent) if temporary_parent else None) as temporary:
        temporary_root = Path(temporary)
        for index, (name, width, height, dark) in enumerate(cases):
            html_path = temporary_root / (name + ".html")
            png_path = temporary_root / (name + ".png")
            html_path.write_text(
                _homepage_document(root, browser, dark), encoding="utf-8"
            )
            dump_profile = temporary_root / "profile-dump-{}".format(index)
            dumped = _run_browser(_browser_command(
                browser,
                dump_profile,
                ("--dump-dom", "--virtual-time-budget=2000"),
                html_path,
                width,
                height,
            ))
            match = RESULT_PATTERN.search(dumped)
            if not match:
                raise ShowcaseRenderError(
                    "browser homepage result missing for {}".format(name)
                )
            try:
                report = json.loads(html.unescape(match.group(1)))
            except (TypeError, ValueError) as error:
                raise ShowcaseRenderError(
                    "invalid homepage browser result for {}: {}".format(name, error)
                )
            if report.get("failures"):
                raise ShowcaseRenderError(
                    "homepage layout failure for {}: {}".format(
                        name, "; ".join(report["failures"])
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
                width,
                height,
            ))
            report["png_bytes"] = _png_dimensions(png_path, (width, height))
            reports[name] = report
    return browser, reports


def check_render(root, assets=None, browser=None):
    root = Path(root).resolve()
    browser = Path(browser).resolve() if browser else discover_browser()
    selected = tuple(assets or generator.generated_asset_paths(root))
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
        browser = Path(args.browser).resolve() if args.browser else discover_browser()
        browser, reports = check_render(args.root, browser=browser)
        _, homepage_reports = check_homepage_render(args.root, browser=browser)
    except (OSError, subprocess.SubprocessError, ShowcaseRenderError) as error:
        print("showcase-render: error: {}".format(error), file=sys.stderr)
        return 2
    print(
        "SHOWCASE_RENDER_PASS browser={} assets={} texts={} regions={} homepage_cases={}".format(
            browser,
            len(reports),
            sum(item["text_count"] for item in reports.values()),
            sum(item["region_count"] for item in reports.values()),
            len(homepage_reports),
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
