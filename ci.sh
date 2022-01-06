#!/usr/bin/env bash


set -ex
set -o pipefail

uname="$(uname -s)"

if [ "$uname" = 'Darwin' ]; then
  system=macos
elif [ "$uname" = 'Linux' ]; then
  system=linux
else
  echo "Unsupported system: $uname"
fi

# "alpha" \
# "arm" \
# "hppa" \
# "i386" \
# "m68k" \
# "mips" \
# "mips64" \
# "mips64el" \
# "mipsel" \
# "ppc" \
# "ppc64" \
# "riscv32" \
# "riscv64" \
# "s390x" \
# "sparc" \
# "sparc64" \

declare -a qemu_platforms=(
  "x86_64"
  "aarch64"
)

declare -A firmwares=(
  ["x86_64"]="
    pc-bios/bios-256k.bin
    pc-bios/efi-e1000.rom
    pc-bios/efi-virtio.rom
    pc-bios/kvmvapic.bin
    pc-bios/vgabios-stdvga.bin"

  ["aarch64"]="
    pc-bios/efi-e1000.rom
    pc-bios/efi-virtio.rom"
)

join() {
  local IFS="$1"
  shift
  echo "$*"
}

install_prerequisite() {
  if [ $system = macos ]; then
    brew install ninja pixman findutils glib
  else
    apk add --no-cache \
      g++ \
      gcc \
      git \
      glib-dev \
      glib-static \
      make \
      musl-dev \
      ninja \
      perl \
      pixman-dev \
      pixman-static \
      pkgconf \
      python3 \
      zlib-static
  fi
}

clone_qemu_repository() {
  git clone \
    --branch v6.0.0 \
    --depth 1 --recurse-submodules \
    https://github.com/qemu/qemu
}

patch_qemu_for_alpine() {
  [ $system = macos ] && return

  pushd qemu > /dev/null

  git apply << EOF
diff --git a/include/hw/s390x/s390-pci-bus.h b/include/hw/s390x/s390-pci-bus.h
index 49ae9f0..2bed491 100644
--- a/include/hw/s390x/s390-pci-bus.h
+++ b/include/hw/s390x/s390-pci-bus.h
@@ -82,7 +82,9 @@ OBJECT_DECLARE_SIMPLE_TYPE(S390PCIIOMMU, S390_PCI_IOMMU)
 #define ZPCI_EDMA_ADDR 0x1ffffffffffffffULL

 #define PAGE_SHIFT      12
-#define PAGE_SIZE       (1 << PAGE_SHIFT)
+#ifndef PAGE_SIZE
+    #define PAGE_SIZE       (1 << PAGE_SHIFT)
+#endif
 #define PAGE_MASK       (~(PAGE_SIZE-1))
 #define PAGE_DEFAULT_ACC        0
 #define PAGE_DEFAULT_KEY        (PAGE_DEFAULT_ACC << 4)
EOF

  popd > /dev/null
}

build_qemu() {
  if [ $system = macos ]; then
    declare -a extra_ldflags=(
      "-framework" "Foundation"
      "-liconv"
      "-lpcre"
      "-lresolv"
      "/usr/local/opt/gettext/lib/libintl.a"
      "/usr/local/opt/glib/lib/libgio-2.0.a"
      "/usr/local/opt/glib/lib/libglib-2.0.a"
      "/usr/local/opt/glib/lib/libgobject-2.0.a"
      "/usr/local/opt/pixman/lib/libpixman-1.a"
      "/usr/local/opt/zstd/lib/libzstd.a"
    )

    local build_flags=''
    local ldflags="$(join ' ' ${extra_ldflags[@]})"
  else
    local build_flags='--static'
    local ldflags=''
  fi

  mkdir -p qemu/build
  pushd qemu/build > /dev/null

  LDFLAGS="$ldflags" \
  ../configure \
    --prefix=/tmp/cross-platform-actions \
    --disable-auth-pam \
    --disable-bsd-user \
    --disable-cfi-debug \
    --disable-cocoa \
    --disable-curses \
    --disable-debug-info \
    --disable-debug-mutex \
    --disable-dmg \
    --disable-docs \
    --disable-gcrypt \
    --disable-gnutls \
    --disable-gtk \
    --disable-guest-agent \
    --disable-guest-agent-msi \
    --disable-hax \
    --disable-kvm \
    --disable-libiscsi \
    --disable-libssh \
    --disable-libusb \
    --disable-linux-user \
    --disable-nettle \
    --disable-parallels \
    --disable-qcow1 \
    --disable-qed \
    --disable-sdl \
    --disable-smartcard \
    --disable-usb-redir \
    --disable-user \
    --disable-vdi \
    --disable-vnc \
    --disable-vvfat \
    --disable-xen \
    --disable-lzo \
    --enable-lto \
    --enable-tools \
    --target-list="$(join , "${qemu_platforms[@]/%/-softmmu}")" \
    $build_flags

  make
  ls -lh
  popd > /dev/null
}

install_xhyve() {
  [ $system != macos ] && return
  brew install --HEAD xhyve
}

bundle_resources() {
  mkdir work
  cp qemu/build/qemu-img work
  tar -C work -c -f "resources-$system.tar" .
  rm -rf work
}

bundle_xhyve() {
  [ $system != macos ] && return

  mkdir -p work/bin
  mv uefi.fd work
  cp "$(which xhyve)" work/bin
  cp "$(brew --cellar xhyve)/$(brew info xhyve --json | jq .[].installed[].version -r)/share/xhyve/test/userboot.so" work
  tar -C work -c -f "xhyve-$system.tar" .
  rm -rf work
}

bundle_qemu() {
  local target_dir='work/qemus'
  mkdir -p "$target_dir"

  for platform in "${qemu_platforms[@]}"; do
    local -a firms=(${firmwares[$platform]})
    local qemu_name=${platform/#/qemu-system-}
    local platform_dir="$target_dir/$qemu_name"
    local firmware_target_dir="$platform_dir/share/qemu"
    local qemu_target_dir="$platform_dir/bin"

    mkdir -p "$firmware_target_dir"
    mkdir -p "$qemu_target_dir"
    cp "qemu/build/$qemu_name" "$qemu_target_dir/qemu"
    cp "${firms[@]/#/qemu/}" "$firmware_target_dir"
    tar -C "$platform_dir" -c -f "$qemu_name-$system.tar" .
  done
}

install_prerequisite
clone_qemu_repository
patch_qemu_for_alpine
build_qemu
install_xhyve
bundle_resources
bundle_xhyve
bundle_qemu
