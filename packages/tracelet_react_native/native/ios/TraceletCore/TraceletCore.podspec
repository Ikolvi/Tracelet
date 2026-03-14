Pod::Spec.new do |s|
  s.name             = 'TraceletCore'
  s.version          = '0.2.4'
  s.summary          = 'Framework-agnostic native engines for Tracelet background geolocation.'
  s.description      = <<-DESC
Shared native Swift engines (LocationEngine, MotionDetector, GeofenceManager,
TraceletDatabase, HttpSyncManager, etc.) used by both the Flutter and React
Native Tracelet plugins. No framework dependencies — pure Apple SDK only.
                       DESC
  s.homepage         = 'https://github.com/Ikolvi/Tracelet'
  s.license          = { :file => '../../../LICENSE' }
  s.author           = { 'Tracelet Contributors' => 'tracelet@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Sources/TraceletCore/**/*.swift'
  s.platform         = :ios, '14.0'
  s.frameworks       = 'CoreLocation', 'CoreMotion', 'UIKit', 'BackgroundTasks', 'AVFoundation', 'AudioToolbox', 'Network'
  s.libraries        = 'sqlite3'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version    = '5.0'
end
