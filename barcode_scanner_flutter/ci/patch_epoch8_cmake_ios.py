#!/usr/bin/env python3
"""Patch epoch8 core/CMakeLists.txt for iOS OpenCV framework + Xcode linkage."""
from __future__ import annotations

import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: patch_epoch8_cmake_ios.py <path-to-core/CMakeLists.txt>", file=sys.stderr)
        return 2

    p = Path(sys.argv[1])
    s = p.read_text(encoding="utf-8")

    ios_block = (
        'if(CMAKE_SYSTEM_NAME STREQUAL "iOS")\n'
        '    get_filename_component(OpenCV_INCLUDE_DIRS_ABS "${OpenCV_INCLUDE_DIRS}" ABSOLUTE)\n'
        '    get_filename_component(OpenCV_FRAMEWORK_DIR_ABS "${OpenCV_FRAMEWORK_DIR}" ABSOLUTE)\n'
        '    set(_opencv2_fw "${OpenCV_FRAMEWORK_DIR_ABS}/opencv2.framework")\n'
        '    if(NOT EXISTS "${_opencv2_fw}")\n'
        '        message(FATAL_ERROR "opencv2.framework not found at ${_opencv2_fw}")\n'
        '    endif()\n'
        '    add_library(opencv2_ios_framework UNKNOWN IMPORTED)\n'
        '    set_target_properties(opencv2_ios_framework PROPERTIES\n'
        '        IMPORTED_LOCATION "${_opencv2_fw}"\n'
        '        INTERFACE_INCLUDE_DIRECTORIES "${OpenCV_INCLUDE_DIRS_ABS}"\n'
        '    )\n'
        '    set(OpenCV_FOUND TRUE)\n'
        '    set(OpenCV_LIBS opencv2_ios_framework)\n'
        'elseif(NOT DEFINED BUILD_FOR_AARM OR NOT BUILD_FOR_AARM)\n'
    )

    needle = "if(NOT DEFINED BUILD_FOR_AARM OR NOT BUILD_FOR_AARM)"
    if needle not in s:
        print("ERROR: epoch8 CMakeLists layout changed: cannot find Linux/Android OpenCV branch", file=sys.stderr)
        return 1
    if 'CMAKE_SYSTEM_NAME STREQUAL "iOS"' not in s:
        s = s.replace(needle, ios_block, 1)
        print("Patched: iOS OpenCV IMPORTED framework + elseif Linux pkg-config branch")
    else:
        print("INFO: iOS OpenCV block already present")

    link_needle = (
        "else()\n"
        "    # Linux build: use opencv_interface from pkg-config\n"
        "    target_link_libraries(ZXing PRIVATE Threads::Threads ${OpenCV_LIBS})"
    )
    link_repl = (
        "else()\n"
        "    # Linux/iOS build: opencv_interface (Linux) or opencv2_ios_framework (iOS)\n"
        "    target_link_libraries(ZXing PRIVATE Threads::Threads ${OpenCV_LIBS})\n"
        "    if(CMAKE_SYSTEM_NAME STREQUAL \"iOS\")\n"
        "        # Do NOT set XCODE_ATTRIBUTE_HEADER_SEARCH_PATHS — it replaces CMake's core/src path.\n"
        "        target_include_directories(ZXing PRIVATE \"${OpenCV_INCLUDE_DIRS_ABS}\")\n"
        "        set_target_properties(ZXing PROPERTIES\n"
        "            XCODE_ATTRIBUTE_FRAMEWORK_SEARCH_PATHS \"${OpenCV_FRAMEWORK_DIR_ABS}\"\n"
        "            XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED NO\n"
        "            XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED NO\n"
        "            XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY \"\"\n"
        "            XCODE_ATTRIBUTE_OTHER_LDFLAGS \"-F${OpenCV_FRAMEWORK_DIR_ABS} -framework opencv2\"\n"
        "        )\n"
        "        target_compile_options(ZXing PRIVATE -Wno-error=undef -Wno-error=return-type)\n"
        "    endif()"
    )
    if link_needle in s and "Linux/iOS build" not in s:
        s = s.replace(link_needle, link_repl, 1)
        print("Patched: ZXing iOS link + Xcode framework paths")
    elif "Linux/iOS build" in s:
        print("INFO: link block already patched")
    else:
        print("WARN: OpenCV link block not found; file layout may have changed")

    # Fix older CI patch that overwrote all header paths (QRVersion.cpp: BitHacks.h not found).
    if 'XCODE_ATTRIBUTE_HEADER_SEARCH_PATHS "${OpenCV_INCLUDE_DIRS_ABS}"' in s:
        s = s.replace(
            '            XCODE_ATTRIBUTE_HEADER_SEARCH_PATHS "${OpenCV_INCLUDE_DIRS_ABS}"\n',
            "",
        )
        print("Patched: removed XCODE_ATTRIBUTE_HEADER_SEARCH_PATHS override")

    p.write_text(s, encoding="utf-8")
    print("Wrote", p)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
