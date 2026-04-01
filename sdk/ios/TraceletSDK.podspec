Pod::Spec.new do |s|
  s.name             = 'TraceletSDK'
  s.version          = '1.0.5'
  s.summary          = 'Tracelet SDK - background geolocation engine'
  s.homepage         = 'https://github.com/Ikolvi/Tracelet'
  s.license          = { :type => 'MIT' }
  s.author           = 'Ikolvi'
  s.source           = { :path => '.' }
  s.ios.deployment_target = '14.0'
  s.swift_version    = '5.9'
  s.source_files     = 'Sources/TraceletSDK/**/*.swift'
  s.frameworks       = 'Foundation', 'CoreLocation', 'Network', 'UIKit'
end
