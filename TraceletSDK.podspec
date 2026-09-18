Pod::Spec.new do |s|
  s.name             = 'TraceletSDK'
  s.version = '3.8.8'
  s.summary          = 'Production-grade background geolocation SDK for iOS.'
  s.description      = <<-DESC
    TraceletSDK provides battery-conscious background geolocation with motion detection,
    geofencing, SQLite persistence, HTTP sync, and headless execution for iOS.
    Framework-agnostic — usable from Flutter, React Native, Capacitor, or native iOS apps.
  DESC
  s.homepage         = 'https://github.com/Ikolvi/Tracelet/tree/main/sdk/ios'
  s.license          = { :type => 'Apache-2.0', :file => 'LICENSE' }
  s.author           = { 'Ikolvi' => 'contact@ikolvi.com' }
  s.source           = { :git => 'https://github.com/Ikolvi/Tracelet.git', :tag => "tracelet_ios-v#{s.version}" }

  s.ios.deployment_target = '14.0'
  s.swift_version = '5.9'

  s.source_files = 'sdk/ios/Sources/TraceletSDK/**/*.swift', 'sdk/ios/Sources/TraceletSDK/*.swift', 'sdk/ios/Sources/TraceletSDK/**/*.h', 'sdk/ios/Sources/TraceletSDK/*.h'
  s.public_header_files = 'sdk/ios/Sources/TraceletSDK/**/*.h', 'sdk/ios/Sources/TraceletSDK/*.h'

  # Apple frameworks
  s.frameworks = 'CoreLocation', 'CoreMotion', 'UIKit', 'BackgroundTasks',
                 'AVFoundation', 'AudioToolbox', 'Network', 'DeviceCheck'

  # System libraries
  s.libraries = 'sqlite3'
  
  # Rust Core
  s.vendored_frameworks = 'sdk/rust-core/out/TraceletCore.xcframework'
  
  s.prepare_command = <<-CMD
    set -e
    if [ ! -d "sdk/rust-core/out/TraceletCore.xcframework" ]; then
      url="https://github.com/Ikolvi/Tracelet/releases/download/tracelet_ios-v#{s.version}/TraceletCore.xcframework.zip"
      echo "Downloading precompiled TraceletCore.xcframework from $url ..."
      mkdir -p sdk/rust-core/out
      if ! curl -fL "$url" -o TraceletCore.xcframework.zip; then
        echo "ERROR: Failed to download TraceletCore.xcframework from $url" >&2
        echo "       Ensure release 'tracelet_ios-v#{s.version}' exists with the asset 'TraceletCore.xcframework.zip'." >&2
        exit 1
      fi
      unzip -o TraceletCore.xcframework.zip -d sdk/rust-core/out/
      rm TraceletCore.xcframework.zip
      if [ ! -d "sdk/rust-core/out/TraceletCore.xcframework" ]; then
        echo "ERROR: TraceletCore.xcframework missing after extraction." >&2
        exit 1
      fi
    else
      echo "Local TraceletCore.xcframework found. Skipping download."
    fi
  CMD

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386 x86_64'
  }
  s.user_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386 x86_64',
    'STRIP_STYLE' => 'non-global'
  }
end
