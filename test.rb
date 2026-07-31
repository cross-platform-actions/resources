#!/usr/bin/env ruby

require "forwardable"
require "minitest/autorun"
require "open3"
require "rubygems"
require "rubygems/package"
require "set"

def execute(command, *args)
  stdout, status = Open3.capture2(command, *args)
  raise "Failed to executed command: #{command} #{args.join(' ')}" unless status.success?
  stdout
end

def qemu_path(architecture)
  "qemu/build/qemu-system-#{architecture}"
end

def assert_qemu_system(architecture, firmwares:)
  validator = QemuSystemValidator.new(architecture, firmwares)
  assert validator.valid?, validator.message
end

def assert_usable_firmwares(architecture)
  validator = FirmwareValidator.new(architecture)
  assert validator.valid?, validator.message
end

def assert_only_system_dependencies(architecture)
  return unless QemuSystemValidator.host_os == "macos"

  allowed_prefixes = Set.new ["/System/Library/Frameworks", "/usr/lib"]
  qemu_path = qemu_path(architecture)
  result = execute "otool", "-L", qemu_path

  non_system_dependecies = result
      .split("\n")
      .drop(1)
      .map(&:strip)
      .reject { |path| allowed_prefixes.any? { path.start_with?(_1) } }
      .map { _1.split.first }

  assert non_system_dependecies.empty?, %("#{qemu_path}" is linked with the following non-system dependencies:\n#{non_system_dependecies.join("\n")})
end

def assert_statically_linked(architecture)
  return unless QemuSystemValidator.host_os == "linux"

  qemu_path = qemu_path(architecture)
  result = execute "file", qemu_path
  statically_linked = result.include?("static-pie linked") || result.include?("statically linked")
  assert statically_linked, %("#{qemu_path}" is not statically linked:\n#{result})
end

describe "resources" do
  describe "qemu-system" do
    describe "x86_64" do
      it "contains the correct file structure for x86_64" do
        assert_qemu_system "x86_64", firmwares: %w[
          bios-256k.bin
          efi-e1000.rom
          efi-virtio.rom
          kvmvapic.bin
          vgabios-stdvga.bin
          uefi.fd
        ]
      end

      it "contains usable firmware files for x86_64" do
        assert_usable_firmwares "x86_64"
      end

      it "is only linked with system dependencies" do
        assert_only_system_dependencies "x86_64"
      end

      it "is statically linked" do
        assert_statically_linked "x86_64"
      end
    end

    describe "arm64" do
      it "contains the correct file structure for arm64" do
        assert_qemu_system "aarch64", firmwares: %w[
          efi-e1000.rom
          efi-virtio.rom
          uefi.fd
        ]
      end

      it "contains usable firmware files for arm64" do
        assert_usable_firmwares "aarch64"
      end

      it "is only linked with system dependencies" do
        assert_only_system_dependencies "aarch64"
      end

      it "is statically linked" do
        assert_statically_linked "aarch64"
      end
    end

    describe "riscv64" do
      it "contains the correct file structure for riscv64" do
        assert_qemu_system "riscv64", firmwares: %w[
          efi-virtio.rom
          opensbi-riscv64-generic-fw_dynamic.bin
          u-boot.bin
        ]
      end

      it "contains usable firmware files for riscv64" do
        assert_usable_firmwares "riscv64"
      end

      it "is only linked with system dependencies" do
        assert_only_system_dependencies "riscv64"
      end

      it "is statically linked" do
        assert_statically_linked "riscv64"
      end
    end
  end
end

class QemuSystemValidator
  attr_reader :firmwares

  def initialize(architecture, firmwares)
    @architecture = architecture
    @firmwares = firmwares.sort
  end

  def self.host_os
    @host_os ||= case Gem::Platform.local.os
      when "darwin"
        "macos"
      when "linux"
        "linux"
      else
        raise "Unsupported platform: #{Gem::Platform.local.os}"
      end
  end

  def valid?
    @valid ||= qemu_binary? && firmware_matching?
  end

  def message
    message_formatter.format
  end

  def tar_file
    @tar_file ||= TarFile.for(architecture: architecture, host_os: host_os)
  end

  def extra
    @extra ||= tar_file.firmwares - firmwares
  end

  def missing
    @missing ||= firmwares - tar_file.firmwares
  end

  private

  attr_reader :architecture

  def qemu_binary?
    tar_file.qemu_binary.any?
  end

  def firmware_matching?
    extra.empty? && missing.empty?
  end

  def message_formatter
    @message_formatter ||= MessageFormatter.new(self)
  end

  def host_os
    self.class.host_os
  end

  class TarFile
    def self.for(architecture:, host_os:)
      new("qemu-system-#{architecture}-#{host_os}.tar")
    end

    def initialize(filename)
      @filename = filename
    end

    attr_reader :filename

    def paths
      @paths ||= File.open(filename) do |io|
        tar_files = []

        Gem::Package::TarReader.new(io) do |tar|
          tar_files = tar
          .filter(&:file?)
          .map(&:full_name)
          .map { _1.delete_prefix("./") }
          .sort
        end

        tar_files
      end
    end

    def firmware_paths
      @firmware_paths ||= paths.filter { _1.start_with?(firmware_directory) }
    end

    # The contents have to be read while the archive is being iterated, an
    # entry cannot be read after the reader has moved past it.
    def firmware_files
      @firmware_files ||= File.open(filename) do |io|
        firmware_files = []

        Gem::Package::TarReader.new(io) do |tar|
          tar.each do |entry|
            next unless firmware?(entry)

            firmware_files << Firmware.new(basename(entry), entry.read.to_s)
          end
        end

        firmware_files
      end
    end

    def qemu_binary
      @qemu_binary ||= paths.filter { _1.start_with?("bin/qemu") }
    end

    def firmwares
      @firmwares ||= firmware_paths.map { _1.delete_prefix(firmware_directory) }
    end

    def firmware_directory
      "share/qemu/"
    end

    private

    def firmware?(entry)
      entry.file? && full_name(entry).start_with?(firmware_directory)
    end

    def basename(entry) = full_name(entry).delete_prefix(firmware_directory)

    def full_name(entry) = entry.full_name.delete_prefix("./")
  end

  class MessageFormatter
    extend Forwardable

    def initialize(validator)
      @validator = validator
    end

    def format
      expected.concat([""], actual, [""], diff).join("\n")
    end

    private

    def_delegators :@validator, :tar_file, :firmwares, :missing, :extra

    def expected
      [
        "Expected '#{tar_file.filename}' to contain:",
        binary_message,
        firmware_message,
      ]
    end

    def actual
      ["Actual:"] + tar_file.paths
    end

    def diff
      missing = to_full_path(self.missing)
      extra = to_full_path(self.extra)

      diff = to_full_path(firmwares)
        .concat(to_full_path(tar_file.firmwares))
        .uniq
        .map { missing.include?(_1) ? "-#{_1}" : _1 }
        .map { extra.include?(_1) ? "+#{_1}" : _1 }

      ["Diff:"] + diff
    end

    def binary_message
      tar_file.qemu_binary
    end

    def firmware_message
      to_full_path(firmwares).join("\n")
    end

    def to_full_path(array)
      array.map { File.join(tar_file.firmware_directory, _1) }
    end
  end
end

# Verifies that the bundled firmware files actually contain firmware. A failed
# download can produce an HTML error or landing page, which is otherwise
# indistinguishable from a correct bundle since the file is still present.
class FirmwareValidator
  def initialize(architecture)
    @architecture = architecture
  end

  def valid? = unusable_firmwares.empty?

  def message
    ["Unusable firmware files in '#{tar_file.filename}':"]
      .concat(unusable_firmwares.map(&:message))
      .join("\n")
  end

  private

  attr_reader :architecture

  def unusable_firmwares
    @unusable_firmwares ||= tar_file.firmware_files.reject(&:usable?)
  end

  def tar_file
    @tar_file ||= QemuSystemValidator::TarFile.for(
      architecture: architecture,
      host_os: QemuSystemValidator.host_os
    )
  end
end

# A single firmware file extracted from a bundle.
class Firmware
  # The smallest firmware bundled, kvmvapic.bin, is a few kilobytes.
  MINIMUM_SIZE = 4096

  private_constant :MINIMUM_SIZE

  HTML_SIGNATURE = /\A\s*<(?:!doctype\s+html|html[\s>])/i

  private_constant :HTML_SIGNATURE

  attr_reader :name

  def initialize(name, content)
    @name = name
    @content = content
  end

  def usable? = !html? && large_enough?

  def message
    return "'#{name}' is an HTML document, not firmware" if html?

    "'#{name}' is #{content.bytesize} bytes, expected at least #{MINIMUM_SIZE}"
  end

  private

  attr_reader :content

  def html? = HTML_SIGNATURE.match?(content.byteslice(0, 1024).b)

  def large_enough? = content.bytesize >= MINIMUM_SIZE
end
