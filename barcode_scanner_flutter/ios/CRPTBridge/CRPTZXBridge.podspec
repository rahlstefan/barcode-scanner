Pod::Spec.new do |s|
  s.name             = 'CRPTZXBridge'
  s.version          = '0.1.0'
  s.summary          = 'Objective-C++ bridge for epoch8 zxing-cpp decoder'
  s.description      = 'Bridge that exposes epoch8 zxing-cpp decode to Swift in Flutter iOS host app.'
  s.homepage         = 'https://github.com/epoch8/zxing-cpp'
  s.license          = { :type => 'Apache-2.0' }
  s.author           = { 'bboxfix' => 'noreply@example.com' }
  s.source           = { :path => '.' }

  s.platform         = :ios, '13.0'
  s.requires_arc     = true
  # UIKit prefix header defines NO; must not be included before OpenCV (via BitMatrix.h).
  s.prefix_header_file = false

  s.source_files     = 'CRPTZXBridge.h', 'CRPTZXBridge.mm'
  s.public_header_files = 'CRPTZXBridge.h'
  # ZXing only — OpenCV is a static iOS framework (must NOT be embedded in Runner.app).
  s.vendored_frameworks = '../third_party/ZXingCpp.xcframework'
  s.frameworks = 'CoreVideo'
  s.libraries = 'c++'

  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'gnu++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    # Device-only ZXingCpp slice from CI (ios-arm64).
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_ROOT}/../third_party/ZXingCpp.xcframework/ios-arm64/ZXing.framework/Headers" "${PODS_ROOT}/../third_party/opencv2.framework/Headers"',
    'FRAMEWORK_SEARCH_PATHS' => '$(inherited) "${PODS_ROOT}/../third_party" "${PODS_ROOT}/../third_party/ZXingCpp.xcframework/ios-arm64"',
    # Link ZXing at build time; link static opencv2 into this target (not into the app bundle).
    'OTHER_LDFLAGS' => '$(inherited) -F"${PODS_ROOT}/../third_party" -framework ZXing -framework opencv2'
  }

  # Runner: embed ZXing only (dynamic). Do not embed opencv2 (invalid CFBundleExecutable for installd).
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '$(inherited) -framework ZXing',
    'FRAMEWORK_SEARCH_PATHS' => '$(inherited) "${PODS_ROOT}/../third_party" "${PODS_ROOT}/../third_party/ZXingCpp.xcframework/ios-arm64"'
  }
end
