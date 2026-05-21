#!/usr/bin/env bash
set -euo pipefail

echo "========= Remove previous builds"
rm -rf _builds
rm -rf ZXingCpp.xcframework

echo "========= Create project structure"
cmake -S../../ -B_builds -GXcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
    -DCMAKE_INSTALL_PREFIX="$(pwd)/_install" \
    -DCMAKE_XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH=NO \
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO \
    -DBUILD_UNIT_TESTS=NO \
    -DBUILD_BLACKBOX_TESTS=NO \
    -DBUILD_EXAMPLES=NO \
    -DBUILD_APPLE_FRAMEWORK=YES \
    -DOpenCV_INCLUDE_DIRS="${OpenCV_INCLUDE_DIRS}" \
    -DOpenCV_FRAMEWORK_DIR="${OpenCV_FRAMEWORK_DIR}"

strip_spurious_opencv_refs() {
  local pbx="_builds/ZXing.xcodeproj/project.pbxproj"
  [ -f "$pbx" ] || return 0
  # Only remove stray OpenCV module link tokens (not arbitrary substrings).
  sed -i "" \
    -e '/-framework opencv_gapi/d' \
    -e '/-framework opencv_highgui/d' \
    -e '/-framework opencv_videoio/d' \
    -e '/-framework opencv_video/d' \
    -e '/-framework opencv_ml/d' \
    -e '/-framework opencv_stitching/d' \
    -e '/-framework opencv_photo/d' \
    -e '/-framework opencv_objdetect/d' \
    "$pbx"
}
strip_spurious_opencv_refs

echo "========= Build the sdk for iOS (device)"
# Do not pass HEADER_SEARCH_PATHS on the command line — it overwrites core/src from CMake.
cmake --build _builds --config Release --target ZXing -- \
  -sdk iphoneos \
  -arch arm64 \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  DEVELOPMENT_TEAM= \
  FRAMEWORK_SEARCH_PATHS="${OpenCV_FRAMEWORK_DIR}"

FRAMEWORK_DEVICE="$(find _builds -type d -path '*Release-iphoneos*/ZXing.framework' | head -n 1)"
if [ -z "${FRAMEWORK_DEVICE}" ] || [ ! -d "${FRAMEWORK_DEVICE}" ]; then
  echo "ERROR: ZXing.framework not found under _builds (Release-iphoneos)"
  find _builds -name 'ZXing.framework' -print || true
  exit 1
fi
echo "Using device framework: ${FRAMEWORK_DEVICE}"

# BUILD_APPLE_FRAMEWORK only copies CMake PUBLIC_HEADERS; Result.h needs DetectorResult.h,
# BitMatrix.h, Matrix.h, etc. Flatten all core/src headers into the framework bundle.
echo "========= Sync ZXing headers into framework (API closure for CRPTZXBridge)"
ZXING_HEADERS_DIR="${FRAMEWORK_DEVICE}/Headers"
SRC_ROOT="$(cd ../../core/src && pwd)"
find "${SRC_ROOT}" -type f -name '*.h' -print0 | while IFS= read -r -d '' h; do
  cp -f "${h}" "${ZXING_HEADERS_DIR}/$(basename "${h}")"
done
echo "Header count in framework: $(find "${ZXING_HEADERS_DIR}" -maxdepth 1 -name '*.h' | wc -l | tr -d ' ')"

BITMATRIX_H="${ZXING_HEADERS_DIR}/BitMatrix.h"
if [ -f "${BITMATRIX_H}" ]; then
  python3 - <<PY
from pathlib import Path
p = Path("${BITMATRIX_H}")
text = p.read_text(encoding="utf-8")
old = '#include "opencv2/opencv.hpp"'
new = "#include <opencv2/core.hpp>\\n#include <opencv2/imgproc.hpp>"
if old in text:
    p.write_text(text.replace(old, new, 1), encoding="utf-8")
    print("Patched BitMatrix.h: opencv.hpp -> core+imgproc (avoids ObjC NO macro)")
else:
    print("WARN: BitMatrix.h missing opencv.hpp include; left unchanged")
PY
fi

echo "========= Create the xcframework (device slice)"
xcodebuild -create-xcframework \
    -framework "${FRAMEWORK_DEVICE}" \
    -output ZXingCpp.xcframework
