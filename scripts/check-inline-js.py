from html.parser import HTMLParser
from pathlib import Path
import subprocess
import tempfile
import sys

PAGES = [
    "index.html", "admin.html", "institution.html", "register.html",
    "packages.html", "verify.html", "certificate.html", "institution-certificate.html",
    "graduate.html", "talent.html", "company.html",
]

class PageMetadata(HTMLParser):
    def __init__(self):
        super().__init__()
        self.html_attrs = {}
        self.has_viewport = False
        self.in_title = False
        self.title_parts = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag.lower() == "html":
            self.html_attrs = attrs
        elif tag.lower() == "meta" and attrs.get("name", "").lower() == "viewport":
            self.has_viewport = True
        elif tag.lower() == "title":
            self.in_title = True

    def handle_data(self, data):
        if self.in_title:
            self.title_parts.append(data)

    def handle_endtag(self, tag):
        if tag.lower() == "title":
            self.in_title = False

class InlineScripts(HTMLParser):
    def __init__(self):
        super().__init__()
        self.in_script = False
        self.external = False
        self.parts = []
        self.scripts = []

    def handle_starttag(self, tag, attrs):
        if tag.lower() == "script":
            self.in_script = True
            self.external = any(k.lower() == "src" and v for k, v in attrs)

    def handle_data(self, data):
        if self.in_script and not self.external:
            self.parts.append(data)

    def handle_endtag(self, tag):
        if tag.lower() == "script" and self.in_script:
            source = "".join(self.parts)
            if source.strip():
                self.scripts.append(source)
            self.parts = []
            self.in_script = False
            self.external = False

failed = False
total_scripts = 0
for page in PAGES:
    path = Path(page)
    if not path.exists():
        print(f"FAIL missing page: {page}")
        failed = True
        continue
    source_text = path.read_text(encoding="utf-8")

    metadata = PageMetadata()
    metadata.feed(source_text)
    title = "".join(metadata.title_parts).strip()
    if metadata.html_attrs.get("lang", "").lower() != "ar" or metadata.html_attrs.get("dir", "").lower() != "rtl":
        print(f"FAIL Arabic RTL document metadata: {page}")
        failed = True
    if not metadata.has_viewport:
        print(f"FAIL missing responsive viewport meta: {page}")
        failed = True
    if "شهادتي العلمية" not in title:
        print(f"FAIL page title does not use the approved brand: {page} ({title})")
        failed = True
    if page in ("certificate.html", "institution-certificate.html"):
        if "@media screen and (max-width: 640px)" not in source_text or "zoom: calc((100vw - 24px) / 1024)" not in source_text:
            print(f"FAIL mobile certificate scaling rules: {page}")
            failed = True
        else:
            print(f"PASS mobile certificate scaling: {page}")

    parser = InlineScripts()
    parser.feed(source_text)
    if not parser.scripts:
        print(f"FAIL no inline JavaScript found: {page}")
        failed = True
    total_scripts += len(parser.scripts)
    for number, source in enumerate(parser.scripts, 1):
        with tempfile.NamedTemporaryFile("w", suffix=".js", encoding="utf-8") as temp:
            temp.write(source)
            temp.flush()
            result = subprocess.run(["node", "--check", temp.name], capture_output=True, text=True)
        if result.returncode:
            print(f"FAIL {page} inline script #{number}")
            print(result.stderr)
            failed = True
        else:
            print(f"PASS {page} inline script #{number}")
if failed:
    sys.exit(1)
print(f"All {total_scripts} inline JavaScript blocks across {len(PAGES)} pages passed syntax validation.")
