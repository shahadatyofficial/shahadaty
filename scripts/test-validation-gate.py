"""Regression checks for the route/helper syntax-validation gate. No network access."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ValidationGateTests(unittest.TestCase):
    def run_gate(self, mutate=None):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "repo"
            shutil.copytree(ROOT, target, ignore=shutil.ignore_patterns(".git", "node_modules"))
            if mutate:
                mutate(target)
            return subprocess.run(
                ["python3", "scripts/check-inline-js.py"], cwd=target,
                capture_output=True, text=True,
            )

    def test_current_routes_pass(self):
        result = self.run_gate()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("graduate-v2.html inline script #2", result.stdout)

    def test_graduate_syntax_failure_is_fatal(self):
        def mutate(root):
            page = root / "graduate-v2.html"
            page.write_text(page.read_text().replace("async function loginGraduate(){", "async function loginGraduate( {", 1))
        result = self.run_gate(mutate)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("FAIL graduate-v2.html inline script #2", result.stdout)

    def test_helper_failure_is_fatal(self):
        result = self.run_gate(lambda root: (root / "egypt-locations.js").write_text("const broken = ;"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("FAIL egypt-locations.js", result.stdout)

    def test_new_route_cannot_skip_validation(self):
        def mutate(root):
            (root / "new-portal.html").write_text('<html lang="ar" dir="rtl"><head><meta name="viewport" content="width=device-width"><title>شهادتي العلمية</title></head><body><script>const broken = ;</script></body></html>')
        result = self.run_gate(mutate)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("FAIL new-portal.html inline script #1", result.stdout)


if __name__ == "__main__":
    unittest.main()
