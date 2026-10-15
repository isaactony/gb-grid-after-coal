"""Capture Metabase dashboards (and each chart on them) as PNGs for the docs.

Drives headless Chrome over the DevTools protocol so it can wait for every query to
finish and the grid layout to settle, then crops each card exactly. Dashboards must have
a public link (Admin → Settings → Public sharing).

    python metabase/screenshots.py --out docs/images \
        britain-after-coal=<public uuid> wind-and-price=<public uuid> ...
"""

import argparse
import base64
import json
import pathlib
import re
import shutil
import subprocess
import tempfile
import time
import urllib.request

import websocket  # websocket-client

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
PORT = 9333
WIDTH = 1400
SCALE = 2

# Skip layout transitions and hide Metabase's chrome around the dashboard.
CSS = """
*, *::before, *::after { transition: none !important; }  /* animations stay on: cards fade in from opacity 0 */
[data-testid="embed-frame-footer"], [data-testid="dashcard"] [data-testid="dashcard-menu"] { display: none !important; }
"""

CARDS_JS = """
(() => {
  const sc = [...document.querySelectorAll('*')].find(e => e.scrollHeight > e.clientHeight + 50
             && /auto|scroll/.test(getComputedStyle(e).overflowY));
  const loading = document.querySelectorAll('[data-testid="loading-indicator"], .LoadingSpinner').length;
  const cards = [...document.querySelectorAll('[data-testid="dashcard"]')].map(el => {
    const r = el.getBoundingClientRect();
    const t = el.querySelector('[data-testid="legend-caption-title"]')?.textContent?.trim()
              || el.querySelector('h1,h2,h3')?.textContent?.trim() || 'text';
    return {title: t, x: r.left, y: r.top, w: r.width, h: r.height};
  });
  return JSON.stringify({height: Math.max(sc ? sc.scrollHeight : 0, document.body.scrollHeight), loading, cards});
})()
"""


class Tab:
    def __init__(self, ws_url):
        self.ws = websocket.create_connection(ws_url, timeout=60, suppress_origin=True)
        self.n = 0

    def call(self, method, **params):
        self.n += 1
        self.ws.send(json.dumps({"id": self.n, "method": method, "params": params}))
        while True:
            msg = json.loads(self.ws.recv())
            if msg.get("id") == self.n:
                if "error" in msg:
                    raise RuntimeError(f"{method}: {msg['error']}")
                return msg.get("result", {})

    def eval(self, js):
        return self.call("Runtime.evaluate", expression=js, returnByValue=True)["result"].get("value")


def slug(text):
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")[:60]


def capture(tab, name, url, out):
    tab.call("Emulation.setDeviceMetricsOverride", width=WIDTH, height=1200, deviceScaleFactor=SCALE, mobile=False)
    tab.call("Page.navigate", url=url)
    time.sleep(3)
    tab.eval(f"document.head.insertAdjacentHTML('beforeend', `<style>{CSS}</style>`)")

    # Grow the viewport to the full dashboard height so nothing scrolls, then wait for queries.
    info = json.loads(tab.eval(CARDS_JS))
    tab.call("Emulation.setDeviceMetricsOverride", width=WIDTH, height=int(info["height"]) + 40,
             deviceScaleFactor=SCALE, mobile=False)
    for _ in range(30):
        time.sleep(1)
        info = json.loads(tab.eval(CARDS_JS))
        if not info["loading"]:
            break
    time.sleep(2)
    info = json.loads(tab.eval(CARDS_JS))

    def shot(path, clip):
        data = tab.call("Page.captureScreenshot", format="png", captureBeyondViewport=False, clip={**clip, "scale": 1})
        path.write_bytes(base64.b64decode(data["data"]))

    cards = info["cards"]
    left = min(c["x"] for c in cards) - 16
    right = max(c["x"] + c["w"] for c in cards) + 16
    bottom = max(c["y"] + c["h"] for c in cards) + 16
    shot(out / f"{name}.png", {"x": left, "y": 0, "width": right - left, "height": bottom})
    for c in cards:
        shot(out / name / f"{slug(c['title'])}.png", {"x": c["x"], "y": c["y"], "width": c["w"], "height": c["h"]})
    print(f"{name}: dashboard + {len(cards)} cards")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("dashboards", nargs="+", help="name=public-uuid")
    p.add_argument("--out", default="docs/images")
    p.add_argument("--base-url", default="http://localhost:3000")
    args = p.parse_args()

    profile = tempfile.mkdtemp(prefix="mb-shots-")
    chrome = subprocess.Popen([CHROME, "--headless=new", f"--remote-debugging-port={PORT}", "--hide-scrollbars",
                               f"--user-data-dir={profile}", "about:blank"],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(50):
            try:
                targets = json.load(urllib.request.urlopen(f"http://127.0.0.1:{PORT}/json"))
                page = next(t for t in targets if t["type"] == "page")
                break
            except Exception:  # noqa: BLE001 — Chrome still starting
                time.sleep(0.2)
        tab = Tab(page["webSocketDebuggerUrl"])
        tab.call("Page.enable")
        for spec in args.dashboards:
            name, uuid = spec.split("=", 1)
            out = pathlib.Path(args.out)
            (out / name).mkdir(parents=True, exist_ok=True)
            capture(tab, name, f"{args.base_url}/public/dashboard/{uuid}", out)
    finally:
        chrome.terminate()
        shutil.rmtree(profile, ignore_errors=True)


if __name__ == "__main__":
    main()
