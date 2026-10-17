"""Check that relative links in the repository's markdown files point to files that exist.

Runs on every pull request (.github/workflows/checks.yml) and anywhere with Python 3:
    python3 tests/ci/check_links.py
External links (http, https, mailto) and anchors within a page are not checked.
"""
import pathlib
import re
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parents[2]
files = subprocess.run(["git", "ls-files", "*.md"], cwd=root, capture_output=True,
                       text=True, check=True).stdout.split()
link = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")
bad = []
for name in files:
    path = root / name
    in_code = False
    for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if line.lstrip().startswith("```"):
            in_code = not in_code
        if in_code:
            continue
        for target in link.findall(line):
            if target.startswith(("http://", "https://", "mailto:", "#")):
                continue
            target = target.split("#")[0]
            if not (path.parent / target).exists():
                bad.append(f"{name}:{lineno}: {target}")

for b in bad:
    print("FAIL  broken link", b)
print(f"{len(files)} markdown files, {len(bad)} broken link(s)")
sys.exit(1 if bad else 0)
