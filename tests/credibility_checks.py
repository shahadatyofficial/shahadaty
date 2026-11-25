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
import json, re, subprocess, sys, tempfile, threading, functools
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
    stats = rpc_stats()
    print("live RPC:", stats)
    httpd = serve()
    try:
        for page in ("index.html", "verify.html"):
            for label, w in (("desktop", 1280), ("mobile", 390)):
                dom, visible, console = render(page, width=w)
                where = "%s/%s" % (page, label)
                for bad in FABRICATED:
                    check("%s: no %r" % (where, bad), bad not in visible)
                for key, field in (("institutions_count", "publicInstCount"),
                                   ("certificates_count", "publicCertCount"),
                                   ("verifications_count", "publicVerifyCount")):
                    pat = r'id="%s"[^>]*>\s*\+?\s*%s\s*<' % (field, ar(stats[key]))
                    check("%s: %s == %s" % (where, field, stats[key]),
                          re.search(pat, dom) is not None)
                check("%s: stats row revealed" % where,
                      re.search(r'id="publicStatsRow" style="(?!display:none)[^"]*"', dom) is not None)
                check("%s: no uncaught console errors" % where,
                      "Uncaught" not in console)
                check("%s: label جهة مسجلة" % where, "جهة مسجلة" in visible)
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
        # RPC failure: rows must stay hidden, no fake numbers, no uncaught errors
        for page in ("index.html", "verify.html"):
            dom, visible, console = render(page, block_rpc=True)
            where = page + "/rpc-down"
            check("%s: stats row stays hidden" % where,
                  'id="publicStatsRow" style="display:none"' in dom)
            check("%s: no uncaught console errors" % where, "Uncaught" not in console)
    finally:
        httpd.shutdown()
    print("\n%d checks failed" % len(FAILS))
    sys.exit(1 if FAILS else 0)

if __name__ == "__main__":
    main()
