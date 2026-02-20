#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint tracelet_ios.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'tracelet_ios'
  s.version          = '0.1.0'
  s.summary          = 'iOS implementation of the Tracelet background geolocation plugin.'
  s.description      = <<-DESC
Production-grade background geolocation for Flutter. Battery-conscious
motion-detection, geofencing, SQLite persistence, HTTP sync, and headless
execution for iOS.
                       DESC
  s.homepage         = 'https://ikolvi.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Tracelet Contributors' => 'tracelet@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '14.0'
  s.frameworks = 'CoreLocation', 'CoreMotion', 'UIKit', 'BackgroundTasks'
  s.libraries = 'sqlite3'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  s.resource_bundles = {'tracelet_ios_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
