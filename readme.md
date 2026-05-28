# Resources

This repository bundles resources used by the
[cross-platform-actions/action](https://github.com/cross-platform-actions/action)
GitHub action.

The following resources are bundled:

* `qemu-img`
* `qemu-system-aarch64`
* `qemu-system-x86_64`

## Releasing

Releases are cut using [relog](https://github.com/jacob-carlborg/relog), which
drives the release from the `[Unreleased]` section of [`changelog.md`](changelog.md).
The changelog follows the [Keep a Changelog](https://keepachangelog.com/) format.

### Prerequisites

Install `relog` (requires Rust 1.85+):

```sh
cargo install --git https://github.com/jacob-carlborg/relog
```

Or download a prebuilt binary from the
[relog releases page](https://github.com/jacob-carlborg/relog/releases) and
place it on your `$PATH`.

### Cutting a release

1. Make sure all changes for the upcoming release are listed under
   `## [Unreleased]` in `changelog.md`, grouped by the appropriate subheaders
   (`### Added`, `### Changed`, `### Deprecated`, `### Removed`, `### Fixed`).
2. Ensure the working tree is clean and you are on the `master` branch.
3. Run `relog` to auto-detect the bump from the changelog, or pass an explicit
   version:

   ```sh
   relog            # auto-detect bump
   relog 1.0.0     # explicit version
   relog --dry-run  # preview without making changes
   ```

4. `relog` will:
   * Insert a `## [X.Y.Z] - YYYY-MM-DD` header and update the reference links
     in `changelog.md`.
   * Commit the changelog and create an annotated `vX.Y.Z` git tag.
   * Prompt before pushing the branch and the tag to `origin`.
5. Pushing the tag triggers the
   [`Create Resource Bundle`](.github/workflows/bundle.yml) workflow, which
   builds the bundle and drafts a GitHub release. Review and publish the draft
   release once it is created.

### Bump detection

The bump type is decided by the `###` subheaders under `## [Unreleased]`:

| Trigger                                          | Bump  |
| ------------------------------------------------ | ----- |
| `### Removed` (or the word "Breaking" anywhere)  | Major |
| `### Added`, `### Changed`, `### Deprecated`     | Minor |
| `### Fixed`                                      | Patch |
