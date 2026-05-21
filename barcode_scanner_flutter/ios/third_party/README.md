Place epoch8 build artifacts here (CI produces both):

- `ZXingCpp.xcframework` — epoch8 `wrappers/ios/build-release.sh` (CI renames output from `ZXing.xcframework`)
- `opencv2.framework` — [opencv-4.10.0-ios-framework.zip](https://github.com/opencv/opencv/releases/download/4.10.0/opencv-4.10.0-ios-framework.zip)

Source: `epoch8/zxing-cpp` branch `crpt-prod-fixed-mediapipe-10.30`.

When `ZXingCpp.xcframework` exists, Podfile uses `CRPTZXBridge` (epoch8 backend). **OpenCV is required** for CRPT DataMatrix; do not disable OpenCV on iOS.

If artifacts are absent locally, build falls back to `ZXingObjC` in `ci/Podfile.template`.
