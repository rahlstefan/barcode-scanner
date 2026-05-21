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
    -DBUILD_UNIT_TESTS=NO \
    -DBUILD_BLACKBOX_TESTS=NO \
    -DBUILD_EXAMPLES=NO \
    -DBUILD_APPLE_FRAMEWORK=YES \
    -DOpenCV_INCLUDE_DIRS="${OpenCV_INCLUDE_DIRS}" \
    -DOpenCV_FRAMEWORK_DIR="${OpenCV_FRAMEWORK_DIR}"

if [ -f _builds/ZXing.xcodeproj/project.pbxproj ]; then
  # Prebuilt opencv2.framework has no arm64-simulator slice; strip bogus module refs from Xcode project.
  sed -i "" \
    -e 's/opencv_gapi//g' \
    -e 's/opencv_highgui//g' \
    -e 's/opencv_videoio//g' \
    -e 's/opencv_video//g' \
    -e 's/opencv_ml//g' \
    -e 's/opencv_stitching//g' \
    -e 's/opencv_photo//g' \
    -e 's/opencv_objdetect//g' \
    _builds/ZXing.xcodeproj/project.pbxproj
fi

XC_OCV=(
  "FRAMEWORK_SEARCH_PATHS=${OpenCV_FRAMEWORK_DIR}"
  "HEADER_SEARCH_PATHS=${OpenCV_INCLUDE_DIRS}"
  "OTHER_LDFLAGS=-F${OpenCV_FRAMEWORK_DIR} -framework opencv2"
)

echo "========= Build the sdk for iOS (device)"
xcodebuild -project _builds/ZXing.xcodeproj build \
    -target ZXing \
    -parallelizeTargets \
    -configuration Release \
    -hideShellScriptEnvironment \
    -sdk iphoneos \
    "${XC_OCV[@]}"

# Official opencv-4.x-ios-framework.zip: device arm64 + x86_64 simulator, not arm64-simulator.
# GitHub macos-15 (Apple Silicon) CI: skip iphonesimulator arm64; unsigned IPA needs device only.
echo "========= Create the xcframework (device slice)"
xcodebuild -create-xcframework \
    -framework ./_builds/core/Release-iphoneos/ZXing.framework \
    -output ZXingCpp.xcframework
