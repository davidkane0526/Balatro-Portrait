"""Regression test: malformed PORTRAIT_CONFIG.version must stop the build.

This intentionally checks both positive and negative cases; previous CI only
compiled the Python build scripts and missed malformed Lua config files.
"""
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import build  # noqa: E402

source = (ROOT / "src/portrait_config.lua").read_text(encoding="utf-8")
assert build._parse_mod_version(source) == "1.0.12"

valid = 'PORTRAIT_CONFIG = {\n    version = "2.1.0",\n    scale_factor = 0.63,\n}\n'
invalid = valid.replace('version = "2.1.0",', 'version = "2.1.0"')
assert build._parse_mod_version(valid) == "2.1.0"
try:
    build._parse_mod_version(invalid)
except RuntimeError as ex:
    assert "comma" in str(ex)
else:
    raise AssertionError("A missing Lua comma was accepted")
print("Config version syntax regression tests passed")
