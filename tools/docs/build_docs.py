#!/usr/bin/env python3
"""Build Fizz Fling's local project record from the notes, 08-record.md and docs/record/."""
import pathlib
import runpy
import subprocess
import sys

PROJECT = pathlib.Path(__file__).resolve().parents[2]
GALLERIES = ["docs/record"]
builder = runpy.run_path(str(pathlib.Path.home() / ".local/bin/docs-build"))
builder["PICTURE_DIRS"].extend(GALLERIES)
builder["build"](PROJECT)
if "--publish" in sys.argv:
    subprocess.run([str(pathlib.Path.home() / ".local/bin/docs-site"), "publish"], check=True)
