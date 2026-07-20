# Resources Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

* Bundle `qemu-system-riscv64` and U-Boot firmware to support FreeBSD RISC-V 64

## [1.0.0] - 2026-05-29

### Changed

* Bump QEMU to 10.2.3

### Removed

* Remove support for xhyve

## [0.12.0] - 2025-11-22

### Changed

* Bump QEMU to 10.1.2

## [0.11.0] - 2024-02-17

### Changed

* Enable hardware acceleration (KVM) on Linux

## [0.10.0] - 2024-01-05

### Added

* Bundle QEMU UEFI for x86-64

### Changed

* Bump QEMU to 8.2.0

## [0.9.1] - 2023-10-07

### Fixed

* Disable `capstone`

## [0.9.0] - 2023-07-25

### Changed

* Bump QEMU to 8.0.3

## [0.8.0] - 2023-06-11

### Changed

* Bump QEMU to 8.0.2

## [0.7.0] - 2023-01-13

### Added

* Bundle Linaro UEFI for ARM64

### Changed

* Bump QEMU to 7.2.0

## [0.6.0] - 2022-08-27

### Added

* Add support for ARM64 as a target architecture

### Changed

* Strip binaries to save space

## [0.5.1] - 2022-07-14

### Fixed

* Bundling of Bhyve UEFI firmware

## [0.5.0] - 2022-05-27

### Added

* Bundle QEMU EFI firmware

## [0.4.0] - 2022-03-18

### Changed

* Bump QEMU to 6.2.0
* The CI script can now be used on Apple Silicon

## [0.3.1] - 2021-12-06

### Changed

* Statically link all non-system provided libraries on macOS

### Fixed

* Missing QEMU dependency glib ([cross-platform-actions/action#5](https://github.com/cross-platform-actions/action/issues/5))

## [0.3.0] - 2021-10-25

### Added

* Bundle missing firmware

### Removed

* Removed all unused architectures. The only remaining one is x86_64

## [0.2.0] - 2021-09-20

### Added

* Add support for the QEMU hypervisor
* Add support for Linux as the host
* Add support for the following target architectures:
    * aarch64
    * alpha
    * arm
    * hppa
    * i386
    * m68k
    * mips
    * mips64
    * mips64el
    * mipsel
    * ppc
    * ppc64
    * riscv32
    * riscv64
    * s390x
    * sparc
    * sparc64
    * x86_64

## [0.0.1] - 2021-05-05

Initial release.

[Unreleased]: https://github.com/cross-platform-actions/resources/compare/v1.0.0...HEAD

[1.0.0]: https://github.com/cross-platform-actions/resources/compare/v0.12.0...v1.0.0
[0.12.0]: https://github.com/cross-platform-actions/resources/compare/v0.11.0...v0.12.0
[0.11.0]: https://github.com/cross-platform-actions/resources/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/cross-platform-actions/resources/compare/v0.9.1...v0.10.0
[0.9.1]: https://github.com/cross-platform-actions/resources/compare/v0.9.0...v0.9.1
[0.9.0]: https://github.com/cross-platform-actions/resources/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/cross-platform-actions/resources/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/cross-platform-actions/resources/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/cross-platform-actions/resources/compare/v0.5.1...v0.6.0
[0.5.1]: https://github.com/cross-platform-actions/resources/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/cross-platform-actions/resources/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/cross-platform-actions/resources/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/cross-platform-actions/resources/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/cross-platform-actions/resources/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/cross-platform-actions/resources/compare/v0.0.1...v0.2.0
[0.0.1]: https://github.com/cross-platform-actions/resources/releases/tag/v0.0.1
