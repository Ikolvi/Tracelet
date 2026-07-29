#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint tracelet_ios.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'tracelet_ios'
  s.version = '3.7.0'
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
  s.dependency 'TraceletSDK', '3.7.0'
  s.platform = :ios, '14.0'
  s.frameworks = 'CoreLocation', 'CoreMotion', 'UIKit', 'BackgroundTasks', 'AVFoundation', 'AudioToolbox', 'Network', 'DeviceCheck'
  s.libraries = 'sqlite3'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 
    'DEFINES_MODULE' => 'YES', 
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'OTHER_LDFLAGS' => '$(inherited) -Wl,-multiply_defined,suppress -Wl,-ld_classic',
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
