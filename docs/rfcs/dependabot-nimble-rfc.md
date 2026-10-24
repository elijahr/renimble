# New Ecosystem Request: Nim (Nimble & Atlas)

## Ecosystem Overview

| Field | Value |
| :--- | :--- |
| **Ecosystem name** | `nimble` |
| **Package manager(s)** | [Nimble](https://github.com/nim-lang/nimble) / [Atlas](https://github.com/nim-lang/atlas) |
| **Primary registry** | [Nim Package Directory (`packages.json`)](https://raw.githubusercontent.com/nim-lang/packages/master/packages.json) / [nimble.directory](https://nimble.directory) |
| **Manifest files** | `*.nimble`, `atlas.config` |
| **Lockfiles** | `nimble.lock` (JSON format v1), `atlas.lock` (JSON format) |

---

## Background

[Nim](https://nim-lang.org/) is a statically typed, compiled systems programming language with clean syntax, expressive metaprogramming, and zero-overhead C/C++/JavaScript compilation targets.

Nimble has served as the official, standard package manager for Nim since 2014, bundled directly in every official compiler release. In addition, [Atlas](https://github.com/nim-lang/atlas) is Nim's modern alternative workspace manager designed by the Nim core team for reproducible, monorepo, and lockfile-first environments.

### Empirical Ecosystem Metrics (Live GitHub API)
- **Active Repositories**: **14,090+ public Nim repositories** on GitHub (`language:nim`).
- **Central Package Registry**: **2,978 packages** indexed in [`nim-lang/packages`](https://github.com/nim-lang/packages).
- **Core Community**: `nim-lang/Nim` (**18,280+ stars**, 1,560+ forks) and `nim-lang/nimble` (**1,400+ stars**, 218 forks).
- **Enterprise & Production Proof**: Major production deployments including Ethereum consensus client ([Nimbus](https://github.com/status-im/nimbus-eth2) securing billions in proof-of-stake value), high-frequency financial trading, and embedded IoT firmware.

Currently, **zero native support exists in Dependabot** for Nim projects. Nim maintainers are forced to manually track upstream releases, run ad-hoc scripts, or build bespoke CI pipelines. Adding `nimble` brings automated security updates and routine version bumping to over 14,000 repositories on GitHub.

---

## Manifest & Lockfile Format

### 1. Nimble Manifest (`*.nimble`)
Nimble manifest files (`<package_name>.nimble`) declare package metadata and dependencies using top-level declarative statements:

```nim
# Package metadata
version       = "1.2.0"
author        = "Jane Doe"
description   = "High-performance cryptographic library"
license       = "MIT"
srcDir        = "src"

# Dependencies
requires "nim >= 2.0.0"
requires "checksums >= 0.1.0", "zippy >= 0.10.4"
requires "ws#head"
requires "react [gui] >= 1.0.0"

task test, "Run the test suite":
  exec "nim c -r tests/test_all.nim"
```

- **Dependency Declarations**: Multiple comma-separated requirements can be combined on a single line or spanned across lines.
- **Constraint Operators**: Standard comparisons (`>=`, `<=`, `>`, `<`, `==`, `!=`), SemVer caret (`^=`), tilde (`~=`), and intersected bounds joined by `&` (e.g. `requires "pkg >= 1.0.0 & <= 1.5.0"`).
- **VCS Pins**: Dependencies can pin to Git branches (`#head`, `#devel`) or commit SHAs (`#a1b2c3d`).
- **Feature Flags**: Optional bracketed flags (e.g. `"pkg [gui] >= 1.0.0"`).

### 2. Lockfile Format (`nimble.lock`)
Standard JSON lockfile format introduced in Nimble 0.14:

```json
{
  "version": 1,
  "packages": {
    "zippy": {
      "version": "0.10.16",
      "vcsRevision": "9a7f3b8c1d2e...",
      "url": "https://github.com/guzba/zippy",
      "downloadMethod": "git"
    },
    "checksums": {
      "version": "0.1.2",
      "vcsRevision": "4e5f6a7b8c9d...",
      "url": "https://github.com/nim-lang/checksums",
      "downloadMethod": "git"
    }
  }
}
```

### 3. Atlas Lockfile (`atlas.lock`)
Atlas projects specify dependencies in `atlas.config` and lock exact SHAs in `atlas.lock`:

```json
{
  "packages": {
    "zippy": {
      "url": "https://github.com/guzba/zippy",
      "commit": "9a7f3b8c1d2e...",
      "version": "0.10.16"
    }
  }
}
```

---

## Implementation Plan

Following the canonical 6-phase rollout defined in [`dependabot-core/NEW_ECOSYSTEMS.md`](https://github.com/dependabot/dependabot-core/blob/main/NEW_ECOSYSTEMS.md) and established by reference implementations (such as [Helm #11726](https://github.com/dependabot/dependabot-core/pull/11726)):

### Phase 1: Core Implementation
Scaffolded via `rake ecosystem:create[nimble]` under `nimble/`:
- `Dependabot::Nimble::FileFetcher`: Locates `*.nimble`, `nimble.lock`, `atlas.config`, and `atlas.lock`. Supports nested directories and monorepos.
- `Dependabot::Nimble::FileParser`: Extracts dependency declarations via static declarative scanning (strictly avoiding arbitrary code execution of task blocks).
- `Dependabot::Nimble::UpdateChecker`: Queries `packages.json` to resolve repository URLs, scans Git tags via `git ls-remote --tags`, evaluates SemVer compatibility, and filters unstable prereleases.
- `Dependabot::Nimble::FileUpdater`: Rewrites `*.nimble` in-place while strictly preserving original indentation (spaces/tabs), quotation styles (single/double), and inline comments. Updates companion `nimble.lock` / `atlas.lock`.
- `Dependabot::Nimble::MetadataFinder`: Extracts changelogs and release notes from upstream GitHub/GitLab releases or repository `CHANGELOG.md` files.
- `Dependabot::Nimble::Version` & `Requirement`: SemVer 2.0 parser with support for caret, tilde, and intersection ranges.

### Phase 2: Advanced Features (Cooldown Support)
- Implements release timestamp extraction from Git tag commit dates and GitHub Releases API (`commit.committer.date` / `tagger.date`).
- Enables Dependabot's cooldown window (`cooldown.default-days` and `cooldown.semver-major-days`) to protect against zero-day supply chain attacks.

### Phase 3: Testing & Validation
- Comprehensive RSpec unit tests covering all core classes (`spec/dependabot/nimble/*_spec.rb`).
- Fixture test coverage on complex real-world manifests (`zippy`, `yaml`, `cligen`).
- Dry-run validation via `bin/dry-run.rb nimble <repo>` verifying lockfile and manifest updates.
- Smoke tests added to `dependabot/smoke-tests`.
- **Target Quality Bar**: Minimum 95% success rate across representative test repositories.

### Phase 4: Coordination with Dependabot Team
- Coordinate API integration and configuration schema additions.
- Ensure Docker container build includes required Git/network tools without requiring heavy language runtimes.
- Wire into Dependabot deployment and CI workflows.

### Phase 5: Beta Release
- Ecosystem released behind the `allow_beta_ecosystems?` feature flag.
- Users opt-in via `.github/dependabot.yml`:
  ```yaml
  version: 2
  enable-beta-ecosystems: true
  updates:
    - package-ecosystem: "nimble"
      directory: "/"
      schedule:
        interval: "weekly"
      cooldown:
        default-days: 3
        semver-major-days: 7
  ```
- Community beta testing across popular Nim GitHub repositories.

### Phase 6: General Availability (GA)
- Remove beta restriction; enable globally across GitHub.com.
- Update GitHub documentation.

---

## Cooldown Implementation

Release dates are obtained from upstream Git tags via the GitHub API or Git commit metadata:

```bash
git log -1 --format=%aI <tag>
```

This returns standard ISO-8601 timestamps, allowing `Dependabot::Nimble::UpdateChecker` to compare release age against configured cooldown thresholds without requiring separate registry metadata APIs.

---

## Technical Challenges & Proposed Solutions

| Challenge | Proposed Solution |
| :--- | :--- |
| **`.nimble` files can contain arbitrary Nim code** | Static declarative parser extracts only `requires` statements outside task blocks. Never invokes the Nim compiler or shell to evaluate the manifest, preventing arbitrary code execution. |
| **Preserving user indentation and formatting** | In-place regex substitution matches the exact declaration line, preserving leading indentation (2-space, 4-space, tabs), trailing inline comments (`# ...`), and single/double quotes. |
| **Transitive lockfile dependency updates** | Direct lockfile JSON updates for exact package pins, with support for delegating to `nimble lock [pkg]` in sandboxed containers when full transitive tree re-resolution is requested. |
| **Git URL dependencies (`requires "https://..."`)** | Parser extracts direct Git URLs and queries remotes directly without requiring central registry resolution. |

---

## Contributor Commitment

I am willing to:
- [x] Implement the core ecosystem classes (`FileFetcher`, `FileParser`, `UpdateChecker`, `FileUpdater`, `MetadataFinder`)
- [x] Write comprehensive unit tests and fixtures
- [x] Maintain the ecosystem during the beta period
- [x] Respond to issues and community feedback
- [x] Update documentation

---

## Questions for Dependabot Team

1. Should we support `atlas.config` / `atlas.lock` under the same `nimble` ecosystem identifier, or would the team prefer a separate ecosystem name (e.g. `atlas`)?
2. Does the team have preferences regarding pure-Ruby lockfile JSON manipulation vs invoking a containerized `nimble lock` helper for transitive tree resolution?
3. Are there specific rate-limiting or caching guidelines for the static `packages.json` registry file?
