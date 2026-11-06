from html.parser import HTMLParser
from pathlib import Path
import subprocess
import tempfile
import sys

PAGES = [
    "index.html", "admin.html", "institution.html", "register.html",
    "packages.html", "verify.html", "certificate.html", "graduate.html", "talent.html",
]

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
    parser = InlineScripts()
    parser.feed(path.read_text(encoding="utf-8"))
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
