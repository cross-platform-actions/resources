#!/usr/bin/env ruby

require "bundler"
require "fileutils"
require "open3"
require "open-uri"
require "tmpdir"

class Qemu
  # Version of QEMU to bundle
  VERSION = "8.0.3"

  # Map of canonicalized host architectures
  ALIASES = {
    aarch64: :arm64
  }.freeze

  # Interface to access which firmware to bundle for each QEMU architecture
  class Architecture
    def initialize(qemu)
      @qemu = qemu
    end

    def name
      self.class.name.split("::").last.downcase
    end

    def bundle
      qemu_target_dir = File.join(architecture_directory, "bin")

      FileUtils.mkdir_p qemu_target_dir
      FileUtils.mkdir_p firmware_target_directory
      bundle_uefi
      FileUtils.cp File.join("qemu", "build", qemu_name), File.join(qemu_target_dir, "qemu")
      FileUtils.cp(firmwares.map { File.join(firmware_source_directory, _1) }, firmware_target_directory)
      execute "tar", "-C", architecture_directory, "-c", "-f", "#{qemu_name}-#{ci_runner.os_name}.tar", "."
    end

    def firmware_target_directory
      File.join(architecture_directory, "share", "qemu")
    end

    def firmware_source_directory
      @firmware_source_directory ||= File.join("qemu", "pc-bios")
    end

    private

    attr_reader :qemu

    def ci_runner
      qemu.ci_runner
    end

    def target_directory
      qemu.target_directory
    end

    def architecture_directory
      File.join(target_directory, qemu_name)
    end

    def qemu_name
      "qemu-system-#{name}"
    end
  end

  class X86_64 < Architecture
    FIRMWARES = %w[
      bios-256k.bin
      efi-e1000.rom
      efi-virtio.rom
      kvmvapic.bin
      vgabios-stdvga.bin
    ].freeze

    private_constant :FIRMWARES

    def firmwares
      FIRMWARES
    end

    def bundle_uefi
      ci_runner.bundle_uefi(firmware_target_directory)
    end
  end

  class Arm64 < Architecture
    FIRMWARES = %w[
      efi-e1000.rom
      efi-virtio.rom
    ].freeze

    private_constant :FIRMWARES

    def name
      "aarch64"
    end

    def firmwares
      FIRMWARES
    end

    def bundle_uefi
      unpack_uefi
      FileUtils.mkdir_p firmware_target_directory
      FileUtils.cp(uefi_source_path, uefi_target_path)

      File.open(uefi_target_path, File::RDWR) do |file|
        file.truncate(file.read.bytes.rindex { _1 != 0 })
      end

      bundle_linaro_uefi
    end

    private

    def uefi_target_path
      @uefi_target_path ||= File.join(firmware_target_directory, "uefi.fd")
    end

    def uefi_source_path
      @uefi_source_path ||= File.join(firmware_source_directory, "edk2-aarch64-code.fd")
    end

    def unpack_uefi
      archive = uefi_source_path + ".bz2"
      return unless File.exist?(archive)

      FileUtils.rm_f uefi_source_path
      execute "bzip2", "-d", archive
    end

    def bundle_linaro_uefi
      download_file(linaro_uefi_url, linaro_uefi_target_path)
    end

    def linaro_uefi_url
      "https://releases.linaro.org/components/kernel/uefi-linaro/latest/release/qemu64/QEMU_EFI.fd"
    end

    def linaro_uefi_target_path
      @linaro_uefi_target_path ||=
        File.join(firmware_target_directory, "linaro_uefi.fd")
    end
  end

  # Specifies which QEMU architectures to bundle for a given host architecture.
  ENABLED_ARCHITECTURES = {
    x86_64: [X86_64, Arm64],
    arm64: [Arm64]
  }.freeze

  attr_reader :ci_runner

  def initialize(ci_runner)
    @ci_runner = ci_runner
  end

  def target_directory
    "work/qemus"
  end

  def fetch
    execute "curl", "-O", "https://download.qemu.org/qemu-#{VERSION}.tar.xz"
    execute "xz -cd qemu-#{VERSION}.tar.xz | tar -xf -"
    FileUtils.rm_rf ["qemu", "qemu-#{VERSION}.tar.xz"]
    FileUtils.ln_s "qemu-#{VERSION}", "qemu"
  end

  def build
    FileUtils.mkdir_p "qemu/build"
    libslirp.build

    Dir.chdir "qemu/build" do
      target_list = enabled_architectures.map { "#{_1.name}-softmmu" }.join(",")
      target_list_arg = "--target-list=" + target_list
      args = %w[
        --prefix=/tmp/cross-platform-actions
        --disable-auth-pam
        --disable-bochs
        --disable-bsd-user
        --disable-capstone
        --disable-cfi-debug
        --disable-curses
        --disable-debug-info
        --disable-debug-mutex
        --disable-dmg
        --disable-docs
        --disable-gcrypt
        --disable-gnutls
        --disable-gtk
        --disable-guest-agent
        --disable-guest-agent-msi
        --disable-hax
        --disable-kvm
        --disable-libiscsi
        --disable-libssh
        --disable-libusb
        --disable-linux-user
        --disable-nettle
        --disable-parallels
        --disable-png
        --disable-qcow1
        --disable-qed
        --disable-replication
        --disable-sdl
        --disable-sdl-image
        --disable-smartcard
        --disable-snappy
        --disable-usb-redir
        --disable-user
        --disable-vde
        --disable-vdi
        --disable-vnc
        --disable-vvfat
        --disable-xen
        --disable-lzo
        --disable-zstd
        --enable-lto
        --enable-slirp
        --enable-tools
      ].append(target_list_arg)
       .concat(ci_runner.qemu_build_flags)

      execute "../configure", *args, env: { LDFLAGS: ldflags }
      execute "make qemu-img qemu-system-aarch64 qemu-system-x86_64"
      execute "ls", "-lh"
    end
  ensure
    libslirp.cleanup
  end

  def bundle
    FileUtils.mkdir_p target_directory
    enabled_architectures.each(&:bundle)
  end

  private

  def ldflags
    ci_runner.qemu_ldflags.concat(libslirp.ldflags).join(" ")
  end

  def libslirp
    ci_runner.host.libslirp
  end

  def enabled_architectures
    @enabled_architectures ||=
      ci_runner.enabled_architectures.map { _1.new(self) }
  end
end

class CIRunner
  def run
    host.install_prerequisite
    qemu.fetch
    qemu.build
    bundle_resources
    host.xhyve.bundle
    qemu.bundle
  end

  def enabled_architectures
    host.qemu.architectures
  end

  def bundle_uefi(firmware_target_dir)
    host.bundle_uefi(firmware_target_dir)
  end

  def os_name
    host.name
  end

  def qemu_build_flags
    host.qemu.build_flags
  end

  def qemu_ldflags
    host.qemu.ldflags
  end

  def host
    @host ||= begin
      os = Gem::Platform.local.os
      host_map[os]&.new or raise "Unsupported operating system: #{os}"
    end
  end

  private

  def host_map
    {
      "darwin" => MacOS,
      "linux" => Linux
    }
  end

  def qemu
    @qemu ||= Qemu.new(self)
  end

  class Host
    def name
      self.class.name.split("::").last.downcase
    end

    class Qemu
      def architectures
        ::Qemu::ENABLED_ARCHITECTURES[architecture]
      end

      private

      def architecture
        @architecture ||= cpu.then { ::Qemu::ALIASES.fetch(_1, _1) }
      end

      def cpu
        Gem::Platform.local.cpu.to_sym
      end
    end
  end

  class MacOS < Host
    def qemu
      @qemu ||= Qemu.new
    end

    def xhyve
      @xhyve ||= begin
        cls = Gem::Platform.local.cpu == "x86_64" ? Xhyve : XhyveNoop
        cls.new(self)
      end
    end

    def libslirp
      @libslirp ||= Libslirp.new
    end

    def bundle_uefi(firmware_target_dir)
      FileUtils.cp "OVMF.fd", File.join(firmware_target_dir, "uefi.fd")
    end

    def install_prerequisite
      packages = %w[ninja pixman glib meson libslirp]
      execute "brew", "install", *packages, env: { HOMEBREW_NO_INSTALL_CLEANUP: true }
      patch_glib_python_codegen
    end

    # Python 3.12 doesn't have the distutils module.
    # Remove when updating to a version of glib newer than 2.78.3.
    def patch_glib_python_codegen
      patch = <<~DIFF
        diff --git a/gio/gdbus-2.0/codegen/utils.py b/gio/gdbus-2.0/codegen/utils.py
        index 02046108dae49efb140c6438b03b80a73770d2c0..08f1ba9731d0582015ef9807eb739a3efa410e0d 100644
        --- a/gio/gdbus-2.0/codegen/utils.py
        +++ b/gio/gdbus-2.0/codegen/utils.py
        @@ -19,7 +19,7 @@
         #
         # Author: David Zeuthen <davidz@redhat.com>

        -import distutils.version
        +import packaging.version
         import os
         import sys

        @@ -166,4 +166,4 @@ def version_cmp_key(key):
                 v = str(key[0])
             else:
                 v = "0"
        -    return (distutils.version.LooseVersion(v), key[1])
        +    return (packaging.version.Version(v), key[1])
      DIFF

      Dir.chdir("/usr/local/Cellar/glib/2.78.3/share/glib-2.0") do
        _, status = Open3.capture2("patch", "-p3", stdin_data: patch)
        raise "Failed to execute 'patch' command" unless status.success?
      end

      execute "pip3", "install", "packaging"
    end

    class Qemu < Host::Qemu
      def build_flags
        []
      end

      def ldflags
        @ldflags ||= [
          "-dead_strip",
          "-framework", "Foundation",
          "-framework", "Cocoa",
          '-lffi',
          "-liconv",
          "-lresolv",
          "#{brew_prefix}/opt/dtc/lib/libfdt.a",
          "#{brew_prefix}/opt/gettext/lib/libintl.a",
          "#{brew_prefix}/opt/glib/lib/libglib-2.0.a",
          "#{brew_prefix}/opt/glib/lib/libgio-2.0.a",
          "#{brew_prefix}/opt/glib/lib/libgmodule-2.0.a",
          "#{brew_prefix}/opt/glib/lib/libgobject-2.0.a",
          "#{brew_prefix}/opt/pixman/lib/libpixman-1.a",
          "#{brew_prefix}/lib/libpcre2-8.a",
          "#{brew_prefix}/lib/libslirp.a"
        ]
      end

      private

      def brew_prefix
        @brew_prefix ||= `brew --prefix`.strip
      end
    end

    private_constant :Qemu

    class Xhyve
      attr_reader :host

      def initialize(host)
        @host = host
      end

      def bundle
        # Reuse previously packaged Xhyve because: "xhyve has been disabled because it does not build"
        # https://github.com/cross-platform-actions/resources/actions/runs/7292733675/job/19874361022#step:3:3225
        download_file("https://github.com/cross-platform-actions/resources/releases/download/v0.9.1/xhyve-macos.tar", "xhyve-#{host.name}.tar")
      end
    end

    private_constant :Xhyve

    class Libslirp
      def build
      end

      def ldflags
        []
      end

      def cleanup
      end
    end

    private_constant :Libslirp
  end

  class Linux < Host
    def qemu
      @qemu ||= Qemu.new
    end

    def xhyve
      @xhyve ||= XhyveNoop.new(self)
    end

    def libslirp
      @libslirp ||= Libslirp.new
    end

    def install_prerequisite
      packages = %w[
        bash
        curl
        g++
        gcc
        glib-dev
        glib-static
        libblkid
        libmount
        make
        meson
        musl-dev
        ninja
        ovmf
        perl
        pixman-dev
        pixman-static
        pkgconf
        python3
        xz
        zlib-static
      ]

      execute "apk", "add", "--no-cache", *packages
    end

    def bundle_uefi(firmware_target_dir)
      FileUtils.cp "/usr/share/OVMF/OVMF.fd", File.join(firmware_target_dir, "uefi.fd")
    end

    class Qemu < Host::Qemu
      def build_flags
        %w[--static]
      end

      def ldflags
        ["-s"]
      end
    end

    private_constant :Qemu

    class Libslirp
      def build
        Dir.chdir(temp_dir) do
          fetch
          _build
        end
      end

      def ldflags
        [File.join(target_path, "build", "libslirp.a")]
      end

      def cleanup
        FileUtils.remove_entry(temp_dir)
      end

      private

      def temp_dir
        @temp_dir ||= Dir.mktmpdir
      end

      def target_path
        @target_path ||= File.join(temp_dir, "libslirp-master")
      end

      def fetch
        download_file("https://gitlab.com/qemu-project/libslirp/-/archive/master/libslirp-master.tar", "libslirp.tar")
        execute "tar", "-xf", "libslirp.tar"
      end

      def _build
        Dir.chdir(target_path) do
          execute "meson", "setup", "-Ddefault_library=static", "build"
          execute "ninja", "-C", "build", "install"
        end
      end
    end

    private_constant :Libslirp
  end

  class XhyveNoop
    def initialize(_host)
    end

    def install
    end

    def bundle
    end
  end

  private

  def bundle_resources
    FileUtils.mkdir_p "work"
    FileUtils.cp_r "qemu/build/qemu-img", "work"
    execute "tar", "-C", "work", "-c", "-f", "resources-#{host.name}.tar", "."
    FileUtils.rm_r "work"
  end
end

def execute(*args, env: {})
  env = env.map { |k, v| [k.to_s, v.to_s] }.to_h
  Kernel.system env, *args, exception: true
end

def download_file(url, destination)
  URI.open(url) do |uri|
    File.open(destination, 'w') { _1.write(uri.read) }
  end
end

CIRunner.new.run
