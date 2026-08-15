# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'open-uri'
require 'tmpdir'

# Flutter installs plugins as `:path` pods, so CocoaPods never downloads
# `s.source :http` (CocoaPods#11867) and skips `prepare_command` — the published
# podspec vendors TraceletSyncFFI.xcframework that nothing ever puts on disk, and
# the build fails at `ld`. Podspec evaluation *does* run for path pods, so fetch
# it from there. SPM gets the same zip through its binaryTarget URL. (#390)
#
# The module is named per package and every path arrives as an argument: the
# sibling copy in tracelet_ios is loaded into the same Ruby process, and a
# shared module plus `__dir__` would let whichever file was required last answer
# for both podspecs.
module TraceletSyncPodspec
  module_function

  # In the monorepo the Rust core is built from source and vended by the
  # TraceletSDK pod, so a download would silently shadow local work. The publish
  # job deletes the root TraceletSDK.podspec, which makes its absence the marker
  # for "this is a published package" — the same signal example/ios/Podfile uses.
  def published?(base_dir)
    !File.exist?(File.expand_path('../../../TraceletSDK.podspec', resolve(base_dir)))
  end

  # Flutter installs plugins through `ios/.symlinks/plugins/<name>`, so the
  # podspec's own directory has to be followed back to the real package before
  # any path relative to it means anything.
  def resolve(base_dir)
    File.realpath(base_dir)
  rescue SystemCallError
    File.expand_path(base_dir)
  end

  def ensure_xcframework!(base_dir, relative_path, url)
    return unless published?(base_dir)

    dest = File.expand_path(relative_path, resolve(base_dir))
    return if File.directory?(dest)

    name = File.basename(dest)
    FileUtils.mkdir_p(File.dirname(dest))
    Kernel.warn("[tracelet] downloading #{name} from #{url}")

    # Staged in a sibling directory, then renamed: an interrupted download must
    # not leave a partial xcframework that every later run treats as complete.
    Dir.mktmpdir("#{name}.", File.dirname(dest)) do |staging|
      zip = File.join(staging, 'download.zip')
      begin
        URI.parse(url).open('rb', open_timeout: 30, read_timeout: 600) do |remote|
          IO.copy_stream(remote, zip)
        end
      rescue StandardError => e
        raise failure(name, url, "download failed: #{e.class}: #{e.message}")
      end

      verify_checksum!(zip, "#{dest}.sha256", name, url)

      unless system('unzip', '-qo', zip, '-d', staging)
        raise failure(name, url, 'unzip failed')
      end

      unpacked = File.join(staging, name)
      raise failure(name, url, "#{name} not found in the archive") unless File.directory?(unpacked)

      File.rename(unpacked, dest) unless File.directory?(dest)
    end
  end

  # The SPM binaryTarget verifies its checksum; the CocoaPods fallback fetches
  # the same zip, so it verifies the same digest. The publish job writes the
  # sidecar next to the podspec. (#390)
  def verify_checksum!(zip, sidecar, name, url)
    return unless File.exist?(sidecar)

    expected = File.read(sidecar).strip
    return if expected.empty?

    actual = Digest::SHA256.file(zip).hexdigest
    return if actual == expected

    raise failure(name, url, "checksum mismatch: expected #{expected}, got #{actual}")
  end

  def failure(name, url, reason)
    <<~MSG
      [tracelet] could not install #{name} (#{reason}).
        Source: #{url}
        Flutter path-installs this pod, so CocoaPods never unpacks s.source and
        the Rust core has to be fetched here instead.
        See https://github.com/Ikolvi/Tracelet/issues/390
    MSG
  end
end
