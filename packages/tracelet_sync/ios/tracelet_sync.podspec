#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint tracelet_sync.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'tracelet_sync'
  s.version = '3.7.4'
  s.summary          = 'iOS implementation of the Tracelet Sync plugin.'
  s.description      = <<-DESC
A new Flutter plugin project.
                       DESC
  s.homepage         = 'https://ikolvi.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'connect@ikolvi.com' }
  s.source           = { :path => '.' }
  s.source_files = 'tracelet_sync/Sources/tracelet_sync/**/*.{swift,h}'
  s.public_header_files = 'tracelet_sync/Sources/tracelet_sync/**/*.h', 'tracelet_sync/Sources/tracelet_sync/*.h'
  s.dependency 'Flutter'
  s.dependency 'TraceletSDK', '3.7.4'
  s.platform = :ios, '14.0'
  s.vendored_frameworks = 'tracelet_sync/TraceletSyncFFI.xcframework'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386', 'STRIP_STYLE' => 'non-global' }
  s.user_target_xcconfig = { 
    'OTHER_LDFLAGS' => '$(inherited) -Wl,-multiply_defined,suppress -Wl,-ld_classic', 
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'DEAD_CODE_STRIPPING' => 'NO',
    'STRIP_STYLE' => 'non-global',
    'STRIP_INSTALLED_PRODUCT' => 'NO'
  }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  s.resource_bundles = {'tracelet_sync_privacy' => ['tracelet_sync/Sources/tracelet_sync/PrivacyInfo.xcprivacy']}
end
