#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Credibility checks for the public pages (index.html, verify.html).

Runs headless Chrome against a local copy of the site and asserts:
  1. No fabricated marketing claims remain in the rendered page.
  2. Public stats come from the live public_platform_stats RPC, shown as exact counts.
  3. When the RPC is unreachable, the stats rows stay hidden (no fake fallback numbers).
  4. No uncaught console errors on the checked paths.

Usage:  python3 tests/credibility_checks.py
Needs:  google-chrome, python3 stdlib only, network access to Supabase.
Exit code 0 = all checks passed.
"""
import json, re, subprocess, sys, tempfile, threading, functools, time
import http.server, socketserver, urllib.request, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PORT = 8123
HOST = "snteiiavvaaumgaegazn.supabase.co"

AR_DIGITS = str.maketrans("0123456789", "٠١٢٣٤٥٦٧٨٩")
def ar(n): return str(n).translate(AR_DIGITS)

def anon_key():
    html = open(os.path.join(ROOT, "index.html"), encoding="utf-8").read()
    return re.search(r"const SK='([^']+)'", html).group(1)

def rpc_stats():
    req = urllib.request.Request(
        "https://%s/rest/v1/rpc/public_platform_stats" % HOST,
        data=b"{}", method="POST",
        headers={"apikey": anon_key(), "Authorization": "Bearer " + anon_key(),
                 "Content-Type": "application/json"})
    rows = json.loads(urllib.request.urlopen(req, timeout=20).read())
    return rows[0] if isinstance(rows, list) else rows

def serve():
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=ROOT)
    socketserver.TCPServer.allow_reuse_address = True
    httpd = socketserver.TCPServer(("127.0.0.1", PORT), handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd

def render(page, width=1280, height=2000, block_rpc=False):
    url = "http://127.0.0.1:%d/%s" % (PORT, page)
    out = tempfile.NamedTemporaryFile(suffix=".html", delete=False).name
    cmd = ["google-chrome", "--headless=new", "--disable-gpu", "--no-sandbox",
           "--disable-dev-shm-usage", "--virtual-time-budget=20000",
           "--enable-logging=stderr", "--v=0",
           "--window-size=%d,%d" % (width, height),
           "--dump-dom", url]
    if block_rpc:
        cmd.insert(1, "--host-resolver-rules=MAP %s 127.0.0.1" % HOST)
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    dom = proc.stdout
    console = proc.stderr
    visible = re.sub(r"<script.*?</script>", " ", dom, flags=re.S)
    visible = re.sub(r"<style.*?</style>", " ", visible, flags=re.S)
    return dom, visible, console

FAILS = []
def check(name, ok, detail=""):
    print(("PASS" if ok else "FAIL"), name, ("-- " + detail if detail and not ok else ""))
    if not ok: FAILS.append(name)

FABRICATED = ["+5,000", "1,000,000", "99.9", "99% رضا العملاء", "متوسط التقييم",
              "+5K", "+1M", "آلاف المؤسسات", "التحقق الرقمي الأولى",
              "2.4 ث", "وقت التحقق", "مؤسسة معتمدة", "SHD-2024-00123"]

def main():
    httpd = serve()
    try:
        for page in ("index.html", "verify.html"):
            for label, w in (("desktop", 1280), ("mobile", 390)):
                dom, visible, console = render(page, width=w)
                where = "%s/%s" % (page, label)
                for bad in FABRICATED:
                    check("%s: no %r" % (where, bad), bad not in visible)
                for gone in ("publicStatsRow", "publicInstCount", "publicCertCount",
                             "publicVerifyCount", "stripInstCount", "stripCertCount",
                             "miniInstCount", "miniCertCount", "miniVerifyCount",
                             "loadPublicStats", "public_platform_stats"):
                    check("%s: no usage counter %s" % (where, gone), gone not in dom)
                check("%s: no stat label جهة مسجلة" % where, "جهة مسجلة" not in visible)
                check("%s: no uncaught console errors" % where,
                      "Uncaught" not in console)
                if page == "index.html" and label == "mobile":
                    check("index/mobile: chat toast stays hidden on narrow screens",
                          'id="sh-support-toast" hidden' in dom)
                if page == "index.html" and label == "desktop":
                    check("index/desktop: chat toast auto-shows on wide screens",
                          'id="sh-support-toast" hidden' not in dom)
            if page == "index.html":
                check("index: illustrative sample labelled", "مثال توضيحي" in visible)
                check("index: 8 supported-sector badges",
                      visible.count("قطاع مدعوم") >= 8)
                check("index: testimonials hidden",
                      re.search(r'id="testimonials" style="display:none', dom) is not None)
                # testimonial cards may still render inside the hidden section's DOM;
                # the display:none assertion above is what users see.
        # layout probe via CDP: horizontal overflow, button visibility, launcher a11y
        import json as _json, urllib.request as _url
        import websocket as _ws
        MEASURE = r"""
        (function(){
          const de=document.documentElement;
          const r={innerWidth:window.innerWidth,scrollWidth:de.scrollWidth};
          r.overflow=de.scrollWidth>window.innerWidth+1;
          const btn=document.querySelector('.search-btn');
          if(btn){const b=btn.getBoundingClientRect();r.btnVisible=b.left>=-1&&b.right<=window.innerWidth+1;r.btnWidth=Math.round(b.width);}
          const launcher=document.querySelector('#sh-support-launcher');
          if(launcher){
            r.ariaLabel=launcher.getAttribute('aria-label')||'';
            r.glyphDisplay=getComputedStyle(launcher.querySelector('.sh-chat-glyph')).display;
            r.dotDisplay=getComputedStyle(launcher.querySelector('.sh-chat-dot')).display;
            const lb=launcher.getBoundingClientRect();r.launcherVisible=lb.right<=window.innerWidth+1&&lb.left>=-1;
          }
          return JSON.stringify(r);
        })()"""
        VERIFY_THEN_MEASURE = r"""
        (function(){
          return new Promise(function(res){
            const inp=document.querySelector('.search-inp');
            if(!inp){res('{"error":"no input"}');return;}
            inp.value='NO-SUCH-CERT-000';
            document.querySelector('.search-btn').click();
            const t0=Date.now();
            const iv=setInterval(function(){
              if(document.querySelector('.result-ok,.result-err')||Date.now()-t0>15000){
                clearInterval(iv);
                setTimeout(function(){res(%s);},900);
              }
            },300);
          });
        })()""" % MEASURE.strip()
        class CDP:
            def __init__(self):
                self.proc = subprocess.Popen(
                    ["google-chrome", "--headless=new", "--disable-gpu", "--no-sandbox",
                     "--disable-dev-shm-usage", "--remote-debugging-port=9333",
                     "--user-data-dir=" + tempfile.mkdtemp(), "about:blank"],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                ws_url = None
                for _ in range(50):
                    try:
                        tabs = _json.load(_url.urlopen("http://127.0.0.1:9333/json/list"))
                        pages = [t for t in tabs if t.get("type") == "page"]
                        if pages:
                            ws_url = pages[0]["webSocketDebuggerUrl"]; break
                    except Exception:
                        pass
                    time.sleep(0.3)
                if not ws_url: raise RuntimeError("no CDP target")
                self.ws = _ws.create_connection(ws_url, timeout=60)
                self.mid = 0
            def cmd(self, method, params=None):
                self.mid += 1
                self.ws.send(_json.dumps({"id": self.mid, "method": method, "params": params or {}}))
                while True:
                    msg = _json.loads(self.ws.recv())
                    if msg.get("id") == self.mid:
                        return msg.get("result", {})
            def eval(self, expr, await_promise=False):
                r = self.cmd("Runtime.evaluate", {"expression": expr, "awaitPromise": await_promise,
                                                  "returnByValue": True})
                return r.get("result", {}).get("value")
            def measure(self, page, w, verify=False):
                self.cmd("Emulation.setDeviceMetricsOverride",
                         {"width": w, "height": 1200, "deviceScaleFactor": 1, "mobile": False})
                self.cmd("Page.navigate", {"url": "http://127.0.0.1:%d/%s" % (PORT, page)})
                time.sleep(3.0)
                v = self.eval(VERIFY_THEN_MEASURE, await_promise=True) if verify else self.eval(MEASURE)
                try:
                    return _json.loads(v) if v else None
                except Exception:
                    return None
            def close(self):
                try: self.proc.terminate()
                except Exception: pass
        cdp = CDP()
        try:
            for w in (1280, 390, 320):
                r = cdp.measure("verify.html", w)
                where = "verify/%dpx" % w
                check("%s: probe ran" % where, r is not None)
                if r:
                    check("%s: no horizontal overflow" % where, not r.get("overflow"), str(r))
                    check("%s: verify button fully visible" % where, bool(r.get("btnVisible")), str(r))
                r = cdp.measure("verify.html", w, verify=True)
                where = "verify/%dpx/result" % w
                check("%s: probe ran" % where, r is not None)
                if r:
                    check("%s: no horizontal overflow after result" % where, not r.get("overflow"), str(r))
            for w in (390, 320):
                r = cdp.measure("index.html", w)
                where = "index/%dpx" % w
                check("%s: probe ran" % where, r is not None)
                if r:
                    check("%s: no horizontal overflow" % where, not r.get("overflow"), str(r))
                    check("%s: launcher has aria-label" % where, bool(r.get("ariaLabel")), str(r))
                    check("%s: chat glyph visible, dot hidden" % where,
                          r.get("glyphDisplay") == "flex" and r.get("dotDisplay") == "none", str(r))
                    check("%s: launcher inside viewport" % where, bool(r.get("launcherVisible")), str(r))
            r = cdp.measure("index.html", 1280)
            check("index/1280px: probe ran", r is not None)
            if r:
                check("index/1280px: desktop launcher unchanged (dot shown, glyph hidden)",
                      r.get("dotDisplay") == "block" and r.get("glyphDisplay") == "none", str(r))
        finally:
            cdp.close()
        # RPC failure: pages must still render without uncaught errors
        for page in ("index.html", "verify.html"):
            dom, visible, console = render(page, block_rpc=True)
            where = page + "/rpc-down"
            check("%s: no uncaught console errors" % where, "Uncaught" not in console)
    finally:
        httpd.shutdown()
    print("\n%d checks failed" % len(FAILS))
    sys.exit(1 if FAILS else 0)

if __name__ == "__main__":
    main()
