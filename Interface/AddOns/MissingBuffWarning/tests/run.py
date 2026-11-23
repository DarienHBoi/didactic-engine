"""Runs MissingBuffWarning (real addon files) against tests/mbw/fakewow.lua.
Each *_test.lua gets a fresh Lua 5.1 state. Usage: python tests/run.py (inside the addon) or python tests/mbw/run.py [addon_dir]"""
import os, sys, glob
from lupa.lua51 import LuaRuntime

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
# default: the addon folder this tests/ folder sits in, else the Salesman workspace copy
_parent = os.path.dirname(HERE)
ADDON = sys.argv[1] if len(sys.argv) > 1 else (
    _parent if os.path.exists(os.path.join(_parent, "Core.lua")) else os.path.join(ROOT, "mbw", "MissingBuffWarning"))

def toc_files():
    out = []
    for line in open(os.path.join(ADDON, "MissingBuffWarning.toc"), encoding="utf-8"):
        line = line.strip()
        if line and not line.startswith("#"):
            out.append(os.path.join(ADDON, line))
    return out

passed = failed = 0
def report(ok, msg):
    global passed, failed
    if ok:
        passed += 1
    else:
        failed += 1
        print("FAIL:", msg)

for test in sorted(glob.glob(os.path.join(HERE, "*_test.lua"))):
    lua = LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    g.report = report
    g.ADDON_FILES = lua.table(*toc_files())
    try:
        lua.execute(open(os.path.join(HERE, "fakewow.lua"), encoding="utf-8").read())
        lua.execute(open(os.path.join(HERE, "helpers.lua"), encoding="utf-8").read())
        lua.execute(open(test, encoding="utf-8").read())
    except Exception as e:
        failed += 1
        print("ERROR in", os.path.basename(test), ":", e)

print(f"{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
