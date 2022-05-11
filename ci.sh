#!/usr/bin/env bash


set -ex
set -o pipefail

uname_s="$(uname -s)"

if [ "$uname_s" = 'Darwin' ]; then
  system=macos
elif [ "$uname_s" = 'Linux' ]; then
  system=linux
else
  echo "Unsupported system: $uname_s"
  exit 1
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

QEMU_VERSION="6.2.0"

uname_m=$(uname -m)

if [ "$uname_m" = "arm64" ]; then
  declare -a qemu_platforms=( \
    "aarch64" \
  )
else
  declare -a qemu_platforms=( \
    "x86_64" \
  )
fi

declare -A firmwares=( \
  ["x86_64"]="\
    pc-bios/bios-256k.bin \
    pc-bios/efi-e1000.rom \
    pc-bios/efi-virtio.rom \
    pc-bios/kvmvapic.bin \
    pc-bios/vgabios-stdvga.bin"

  ["aarch64"]="\
    pc-bios/efi-e1000.rom \
    pc-bios/efi-virtio.rom \
    pc-bios/edk2-aarch64-code.fd"
)

join() {
  local IFS="$1"
  shift
  echo "$*"
}

install_prerequisite() {
  if [ $system = macos ]; then
    HOMEBREW_NO_INSTALL_CLEANUP=true
    brew install ninja pixman glib
    [ -n "$GITHUB_ACTIONS" ] || brew install jq xz
  else
    apk add --no-cache \
      curl \
      g++ \
      gcc \
      glib-dev \
      glib-static \
      make \
      musl-dev \
      ninja \
      ovmf \
      perl \
      pixman-dev \
      pixman-static \
      pkgconf \
      python3 \
      xz \
      zlib-static
  fi
}

fetch_qemu() {
  curl -O https://download.qemu.org/qemu-$QEMU_VERSION.tar.xz
  xz -cd qemu-$QEMU_VERSION.tar.xz | tar -xf -
  rm -rf qemu && ln -s qemu-$QEMU_VERSION qemu
}

build_qemu() {
  if [ $system = macos ]; then
    local PREFIX=$(brew config | awk '/HOMEBREW_PREFIX/ { print $2; }')

    declare -a extra_ldflags=(
      "-framework" "Foundation"
      "-liconv"
      "-lpcre"
      "-lresolv"
      "$PREFIX/opt/gettext/lib/libintl.a"
      "$PREFIX/opt/glib/lib/libgio-2.0.a"
      "$PREFIX/opt/glib/lib/libglib-2.0.a"
      "$PREFIX/opt/glib/lib/libgmodule-2.0.a"
      "$PREFIX/opt/glib/lib/libgobject-2.0.a"
      "$PREFIX/opt/pixman/lib/libpixman-1.a"
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
    --disable-bochs \
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
    --disable-replication \
    --disable-sdl \
    --disable-smartcard \
    --disable-snappy \
    --disable-usb-redir \
    --disable-user \
    --disable-vde \
    --disable-vdi \
    --disable-vnc \
    --disable-vvfat \
    --disable-xen \
    --disable-lzo \
    --disable-zstd \
    --enable-lto \
    --enable-slirp=git \
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
  mkdir -p work
  cp qemu/build/qemu-img work
  tar -C work -c -f "resources-$system.tar" .
  rm -rf work
}

bundle_xhyve() {
  [ $system != macos ] && return

  mkdir -p work/bin
  [ -n "$GITHUB_ACTIONS" ] && mv uefi.fd work
  cp "$(which xhyve)" work/bin
  cp "$(brew --cellar xhyve)/$(brew info xhyve --json | jq .[].installed[].version -r)/share/xhyve/test/userboot.so" work
  tar -C work -c -f "xhyve-$system.tar" .
  rm -rf work
}

bundle_uefi() {
  [ $system = macos ] && return
  local firmware_target_dir="$1"
  cp /usr/share/OVMF/OVMF.fd "$firmware_target_dir"
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
    if [ -f qemu/pc-bios/edk2-aarch64-code.fd.bz2 ]; then
      rm -f qemu/pc-bios/edk2-aarch64-code.fd
      bzip2 -d qemu/pc-bios/edk2-aarch64-code.fd.bz2
    fi

    bundle_uefi "$firmware_target_dir"
    cp "qemu/build/$qemu_name" "$qemu_target_dir/qemu"
    cp "${firms[@]/#/qemu/}" "$firmware_target_dir"
    tar -C "$platform_dir" -c -f "$qemu_name-$system.tar" .
  done
}

install_prerequisite
fetch_qemu
build_qemu
bundle_resources
if [ "$uname_m" = "x86_64" ]; then
  install_xhyve
  bundle_xhyve
fi
bundle_qemu
