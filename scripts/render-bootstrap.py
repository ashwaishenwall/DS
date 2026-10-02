#!/usr/bin/env python3
import sys
from pathlib import Path

if len(sys.argv) < 3:
    raise SystemExit("usage: render-bootstrap.py INPUT OUTPUT [key=value ...]")

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
s = src.read_text()
s = s.replace("%%{", "%{").replace("$${", "${")
for item in sys.argv[3:]:
    key, value = item.split("=", 1)
    s = s.replace("${" + key + "}", value)
dst.write_text(s)
dst.chmod(0o750)
