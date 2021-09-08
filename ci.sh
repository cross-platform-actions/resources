#!/bin/bash

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

declare -a qemu_platforms=( \
  "aarch64" \
  "alpha" \
  "arm" \
  "hppa" \
  "i386" \
  "m68k" \
  "mips" \
  "mips64" \
  "mips64el" \
  "mipsel" \
  "ppc" \
  "ppc64" \
  "riscv32" \
  "riscv64" \
  "s390x" \
  "sparc" \
  "sparc64" \
  "x86_64" \
)

join() {
  local IFS="$1"
  shift
  echo "$*"
}

install_prerequisite() {
  if [ $system = macos ]; then
    brew install ninja pixman findutils
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
    local build_flags=''
  else
    local build_flags='--static'
  fi

  mkdir -p qemu/build
  pushd qemu/build > /dev/null

  ../configure \
    --disable-auth-pam \
    --disable-bsd-user \
    --disable-cfi-debug \
    --disable-cocoa \
    --disable-curses \
    --disable-debug-info \
    --disable-debug-mutex \
    --disable-dmg \
    --disable-docs \
    --disable-gtk \
    --disable-guest-agent \
    --disable-guest-agent-msi \
    --disable-kvm \
    --disable-libusb \
    --disable-linux-user \
    --disable-parallels \
    --disable-qcow1 \
    --disable-qed \
    --disable-sdl \
    --disable-smartcard \
    --disable-usb-redir \
    --disable-user \
    --disable-vnc \
    --disable-vvfat \
    --disable-xen \
    --disable-hax \
    --disable-vdi \
    --enable-tools \
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
  if [ $system = macos ]; then
    mkdir work
    mv uefi.fd work
    cp qemu/build/qemu-img work
    cp "$(which xhyve)" work
    cp "$(brew --cellar xhyve)/$(brew info xhyve --json | jq .[].installed[].version -r)/share/xhyve/test/userboot.so" work
  else
    mkdir work
    cp qemu/build/qemu-img work
    cp /lib/ld-musl-x86_64.so.1 work
  fi

  tar -C work -c -f "resources-$system.tar" .
  rm -rf work
}

bundle_qemu() {
  local target_dir='work/qemus'
  mkdir -p "$target_dir"

  for platform in "${qemu_platforms[@]/#/qemu-system-}"; do
    mkdir "$target_dir/$platform"
    cp "qemu/build/$platform" "$target_dir/$platform/qemu"
    tar -C "$target_dir/$platform" -c -f "$platform-$system.tar" .
  done
}

install_prerequisite
clone_qemu_repository
patch_qemu_for_alpine
build_qemu
install_xhyve
bundle_resources
bundle_qemu
