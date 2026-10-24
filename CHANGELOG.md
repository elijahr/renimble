# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Fixed
- **Adversarial Audit Pillar 1 (Shelfware Integration)**: Wired `compiler.nim` version synchronization into `renimble.nim` to update GitHub Actions workflows (`.github/workflows/*.yml`), asdf / mise (`.tool-versions`), and mise (`.mise.toml`) upon compiler bumps.
- **Adversarial Audit Pillar 1 (GitOps PR Lifecycle)**: Implemented `createPullRequest` in `pr.nim` and integrated end-to-end branch push and PR creation in CI mode (`cmCi`).
- **Adversarial Audit Pillar 2 (Robust Tag Parsing)**: Hardened `upstream.nim:parseGitLsRemoteTags` against non-SemVer Git tags (e.g. `nightly`, `devel`, `alpha`), preventing unhandled `ValueError` crashes.
- **Adversarial Audit Pillar 2 (Prerelease Suppression)**: Configured `upstream.nim:getLatestRelease` to prioritize stable releases over unstable alphas/betas by default unless tracking prereleases.
- **Adversarial Audit Pillar 2 (HTTP Client Cleanup)**: Ensured `registry.nim:fetchRegistry` closes HTTP connections via `finally: client.close()`.
- **Adversarial Audit Pillar 3 (Interval Tree `!=` Deconstruction)**: Replaced degenerate empty interval representation of `voNe` with `singleConstraintToIntervals` decomposing `!=` into disjoint intervals `(-inf, target) U (target, +inf)`.
- **Adversarial Audit Pillar 3 (URL Lockfile Recognition)**: Fixed `lockfile.nim:findDanglingDependencies` to recognize canonical cleaned package names from URL requirements, eliminating false-positive dangling warnings.
- **Adversarial Audit Pillar 4 (Carcass Purge)**: Purged obsolete `DependanimConfig` legacy alias from `types.nim` and eliminated duplicate `cleanPkgName` and `isRequiresStatement` definitions.
- **Adversarial Audit Pillar 5 (Green Mirage Elimination)**: Replaced loose substring test assertions with exact structural object equality across compiler and workflow updaters, added negative controls for invalid tags, prereleases, and URL requirements.

### Added
- Add real-world Nimble package fixtures (zippy, yaml, cligen, multi-line requires, #head pins, feature flags) and full local Git operations engine in pr.nim with CLI integration
- Add comprehensive adversarial test suite and negative controls (19 tests) with hardened parser, rewriter, and lockfile validation

