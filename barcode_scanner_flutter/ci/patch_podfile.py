#!/usr/bin/env python3
"""Patch the Flutter-generated ios/Podfile to:
  * pin platform to iOS 13.0 (TensorFlowLiteSwift requires >= 12.0)
  * add `pod 'TensorFlowLiteSwift', '~> 2.14.0'` inside `target 'Runner' do`
Idempotent. Externalised from the workflow YAML to avoid quoting hell.
"""
import re
import sys
from pathlib import Path

PODFILE = Path("ios/Podfile")

if not PODFILE.exists():
    sys.stderr.write(f"ERROR: {PODFILE} not found\n")
    sys.exit(1)

src = PODFILE.read_text(encoding="utf-8")
original = src

# 1. Force platform :ios, '13.0'
if re.search(r"^# *platform :ios", src, flags=re.M):
    src = re.sub(
        r"^# *platform :ios.*$",
        "platform :ios, '13.0'",
        src,
        count=1,
        flags=re.M,
    )
elif re.search(r"^platform :ios", src, flags=re.M):
    src = re.sub(
        r"^platform :ios.*$",
        "platform :ios, '13.0'",
        src,
        count=1,
        flags=re.M,
    )
else:
    src = "platform :ios, '13.0'\n" + src

# 2. Add TFLite pod inside Runner target.
if "TensorFlowLiteSwift" not in src:
    new_src, n = re.subn(
        r"(target 'Runner' do[^\n]*\n)",
        r"\1  pod 'TensorFlowLiteSwift', '~> 2.14.0'\n",
        src,
        count=1,
    )
    if n == 0:
        sys.stderr.write("ERROR: could not locate `target 'Runner' do` in Podfile\n")
        sys.stderr.write(src)
        sys.exit(2)
    src = new_src

if src != original:
    PODFILE.write_text(src, encoding="utf-8")

print("--- Podfile after patch ---")
print(src)
