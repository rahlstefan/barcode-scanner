Place epoch8 build artifact here:

- Expected path: `ios/third_party/ZXingCpp.xcframework`
- Source: `epoch8/zxing-cpp` branch `crpt-prod-fixed-mediapipe-10.30`
- Build script: `wrappers/ios/build-release.sh`

When this xcframework exists, CI and Podfile will use `CRPTZXBridge` (epoch8 backend).
If it is absent, build falls back to `ZXingObjC` backend.
