Pod::Spec.new do |s|
  s.name             = 'TraceletSDK'
  s.version          = '0.1.0'
  s.summary          = 'Production-grade background geolocation SDK for iOS.'
  s.description      = <<-DESC
    TraceletSDK provides battery-conscious background geolocation with motion detection,
    geofencing, SQLite persistence, HTTP sync, and headless execution for iOS.
    Framework-agnostic — usable from Flutter, React Native, Capacitor, or native iOS apps.
  DESC
  s.homepage         = 'https://github.com/Ikolvi/Tracelet'
  s.license          = { :type => 'Apache-2.0', :file => '../../LICENSE' }
  s.author           = { 'Ikolvi' => 'contact@ikolvi.com' }
  s.source           = { :git => 'https://github.com/Ikolvi/Tracelet.git', :tag => "sdk-ios-v#{s.version}" }

  s.ios.deployment_target = '14.0'
  s.swift_version = '5.9'

  s.source_files = 'Sources/TraceletSDK/**/*.swift'

  # Apple frameworks
  s.frameworks = 'CoreLocation', 'CoreMotion', 'UIKit', 'BackgroundTasks',
                 'AVFoundation', 'AudioToolbox', 'Network', 'DeviceCheck'

  # System libraries
  s.libraries = 'sqlite3'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
end
