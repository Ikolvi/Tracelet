#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint tracelet_ios.podspec` to validate before publishing.
#
# Fetches the vendored Rust core in published packages, where CocoaPods will
# not do it for us. No-op in the monorepo. (#390)
require File.expand_path('ensure_xcframework', File.dirname(__FILE__))

Pod::Spec.new do |s|
  s.name             = 'tracelet_ios'
  s.version = '3.8.8'
  s.summary          = 'iOS implementation of the Tracelet background geolocation plugin.'
  s.description      = <<-DESC
Production-grade background geolocation for Flutter. Battery-conscious
motion-detection, geofencing, SQLite persistence, HTTP sync, and headless
execution for iOS.
                       DESC
  s.homepage         = 'https://github.com/Ikolvi/Tracelet'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Tracelet Contributors' => 'tracelet@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'tracelet_ios/Sources/tracelet_ios/**/*.{swift,h}'
  s.public_header_files = 'tracelet_ios/Sources/tracelet_ios/**/*.h'
  s.dependency 'Flutter'
  s.dependency 'TraceletSDK', '3.8.8'
  s.platform = :ios, '14.0'
  s.frameworks = 'CoreLocation', 'CoreMotion', 'UIKit', 'BackgroundTasks', 'AVFoundation', 'AudioToolbox', 'Network', 'DeviceCheck'
  s.libraries = 'sqlite3'

  # Published packages vendor TraceletCore.xcframework but ship without it:
  # Flutter installs plugins as :path pods, and CocoaPods downloads neither
  # `s.source :http` nor `prepare_command` for those. Podspec evaluation is the
  # one hook that does run, so fetch it here. No-op in the monorepo. (#390)
  TraceletIosPodspec.ensure_xcframework!(
    File.dirname(__FILE__),
    'TraceletCore.xcframework',
    "https://github.com/Ikolvi/Tracelet/releases/download/tracelet_ios-v#{s.version}/TraceletCore.xcframework.zip"
  )

  # CocoaPods links a *dependency's* vendored frameworks into a pod target but
  # never the pod's own, so the UniFFI bindings compiled into this pod would
  # find no definitions for uniffi_tracelet_core_* at link time. Only published
  # packages vendor the core directly; in the monorepo it arrives through the
  # TraceletSDK dependency and CocoaPods links it already. (#390)
  core_ldflags = TraceletIosPodspec.published?(File.dirname(__FILE__)) ? ' -framework "TraceletCore"' : ''

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'OTHER_LDFLAGS' => '$(inherited) -Wl,-multiply_defined,suppress -Wl,-ld_classic' + core_ldflags,
    'STRIP_STYLE' => 'non-global'
  }
  s.user_target_xcconfig = { 
    'OTHER_LDFLAGS' => '$(inherited) -Wl,-multiply_defined,suppress -Wl,-ld_classic',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'DEAD_CODE_STRIPPING' => 'NO',
    'STRIP_STYLE' => 'non-global',
    'STRIP_INSTALLED_PRODUCT' => 'NO'
  }
  s.swift_version = '5.0'

  s.resource_bundles = {'tracelet_ios_privacy' => ['tracelet_ios/Sources/tracelet_ios/PrivacyInfo.xcprivacy']}
end
