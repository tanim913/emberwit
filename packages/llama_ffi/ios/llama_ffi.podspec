# CocoaPods build of llama_ffi, used only when Swift Package Manager is
# disabled for the app. Run ios/fetch_xcframework.sh first: it downloads the
# same pinned llama.cpp xcframework that ios/llama_ffi/Package.swift uses.
Pod::Spec.new do |s|
  s.name             = 'llama_ffi'
  s.version          = '0.1.0'
  s.summary          = 'llama.cpp for Emberwit through dart:ffi.'
  s.description      = 'Links the official llama.cpp xcframework (CPU + Metal).'
  s.homepage         = 'https://github.com/ggml-org/llama.cpp'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Emberwit' => 'dev@emberwit.app' }
  s.source           = { :path => '.' }
  s.source_files     = 'llama_ffi/Sources/llama_ffi/**/*.swift'
  s.vendored_frameworks = 'Frameworks/llama.xcframework'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
