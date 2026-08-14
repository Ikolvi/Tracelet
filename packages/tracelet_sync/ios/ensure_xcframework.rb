# frozen_string_literal: true

require 'fileutils'
require 'open-uri'

# Flutter installs plugins as :path pods, so CocoaPods never downloads
# `s.source :http` (CocoaPods#11867) and skips `prepare_command`. Fetch the
# GitHub Release xcframework when it is not already on disk. (#390)
#
# A module (not a top-level method) so the call is valid both outside the
# podspec DSL and inside CocoaPods' instance_eval of the spec block.
module TraceletPodspec
  module_function

  def ensure_xcframework!(relative_path, url)
    dest = File.expand_path(relative_path, __dir__)
    return if File.directory?(dest)

    zip_path = "#{dest}.download.zip"
    FileUtils.mkdir_p(File.dirname(dest))
    Kernel.warn("[tracelet] downloading #{File.basename(dest)} from #{url}")
    URI.open(url) { |remote| File.binwrite(zip_path, remote.read) }
    ok = system('unzip', '-qo', zip_path, '-d', File.dirname(dest))
    FileUtils.rm_f(zip_path)
    return if ok && File.directory?(dest)

    raise <<~MSG
      Failed to fetch #{File.basename(dest)} from #{url}.
      Flutter path-installs this pod, so CocoaPods never unpacks s.source.
      See https://github.com/Ikolvi/Tracelet/issues/390
    MSG
  end
end
