#!/usr/bin/env ruby

require "forwardable"
require "minitest/autorun"
require "rubygems"
require "rubygems/package"

def assert_qemu_system(architecture, firmwares:)
  validator = QemuSystemValidator.new(architecture, firmwares)
  assert validator.valid?, validator.message
end

describe "resources" do
  describe "qemu-system" do
    describe "x86_64" do
      it "contains the correct file structure for x86_64" do
        uefi = Gem::Platform.local.os == "darwin" ? [] : ["uefi.fd"]

        assert_qemu_system "x86_64", firmwares: %w[
          bios-256k.bin
          efi-e1000.rom
          efi-virtio.rom
          kvmvapic.bin
          vgabios-stdvga.bin
        ].concat(uefi)
      end
    end

    describe "arm64" do
      it "contains the correct file structure for arm64" do
        assert_qemu_system "aarch64", firmwares: %w[
          efi-e1000.rom
          efi-virtio.rom
          uefi.fd
          linaro_uefi.fd
        ]
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

  def valid?
    @valid ||= qemu_binary? && firmware_maching?
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

  def firmware_maching?
    extra.empty? && missing.empty?
  end

  def message_formatter
    @message_formatter ||= MessageFormatter.new(self)
  end

  def host_os
    @host_os ||= case Gem::Platform.local.os
      when "darwin"
        "macos"
      when "linux"
        "linux"
      else
        raise "Unsupported platform: #{Gem::Platform.local.os}"
      end
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

    def qemu_binary
      @qemu_binary ||= paths.filter { _1.start_with?("bin/qemu") }
    end

    def firmwares
      @firmwares ||= firmware_paths.map { _1.delete_prefix(firmware_directory) }
    end

    def firmware_directory
      "share/qemu/"
    end
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
