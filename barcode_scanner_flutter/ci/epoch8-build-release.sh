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
cmake --build _builds --config Release --target ZXing -- \
  -sdk iphoneos \
  -arch arm64 \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  DEVELOPMENT_TEAM= \
  FRAMEWORK_SEARCH_PATHS="${OpenCV_FRAMEWORK_DIR}" \
  HEADER_SEARCH_PATHS="${OpenCV_INCLUDE_DIRS}"

FRAMEWORK_DEVICE="$(find _builds -type d -path '*Release-iphoneos*/ZXing.framework' | head -n 1)"
if [ -z "${FRAMEWORK_DEVICE}" ] || [ ! -d "${FRAMEWORK_DEVICE}" ]; then
  echo "ERROR: ZXing.framework not found under _builds (Release-iphoneos)"
  find _builds -name 'ZXing.framework' -print || true
  exit 1
fi
echo "Using device framework: ${FRAMEWORK_DEVICE}"

echo "========= Create the xcframework (device slice)"
xcodebuild -create-xcframework \
    -framework "${FRAMEWORK_DEVICE}" \
    -output ZXingCpp.xcframework
