Pod::Spec.new do |s|
  s.name             = 'TraceletReactNative'
  s.version          = '0.1.0'
  s.summary          = 'React Native bridge for Tracelet background geolocation.'
  s.description      = <<-DESC
Production-grade background geolocation for React Native. Battery-conscious
motion-detection, geofencing, SQLite persistence, HTTP sync, and headless
execution. Powered by TraceletCore shared native engines.
                       DESC
  s.homepage         = 'https://github.com/Ikolvi/Tracelet'
  s.license          = { :type => 'Apache-2.0', :file => '../../../LICENSE' }
  s.author           = { 'Tracelet Contributors' => 'tracelet@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Sources/**/*.{swift,m,mm}'
  s.dependency       'React-Core'
  # TraceletCore is bundled — use subspec to compile sources inline
  s.dependency       'TraceletCore'
  s.platform         = :ios, '14.0'
  s.frameworks       = 'CoreLocation', 'CoreMotion', 'UIKit', 'BackgroundTasks'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'SWIFT_OBJC_BRIDGING_HEADER' => '',
  }
  s.swift_version    = '5.0'
end
