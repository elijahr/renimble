# New Ecosystem Request: Nim (Nimble & Atlas)

## Ecosystem Overview

| Field | Value |
| :--- | :--- |
| **Ecosystem Name** | `nimble` |
| **Package Manager(s)** | [Nimble](https://github.com/nim-lang/nimble) / [Atlas](https://github.com/nim-lang/atlas) |
| **Primary Registry** | [Nim Package Directory (`packages.json`)](https://raw.githubusercontent.com/nim-lang/packages/master/packages.json) / [nimble.directory](https://nimble.directory) |
| **Manifest Files** | `*.nimble`, `atlas.config` |
| **Lockfiles** | `nimble.lock` (JSON format), `atlas.lock` (JSON format) |

---

## 1. Background & Motivation

[Nim](https://nim-lang.org/) is a statically typed, compiled systems programming language that compiles to C, C++, and JavaScript. It combines the expressive syntax of Python with the raw execution speed and memory efficiency of C.

Nimble is the official, ubiquitous package manager for Nim, bundled with the Nim compiler distribution since Nim 0.15 (2016). Over 2,500 active packages are registered in the central Nimble package directory, spanning web frameworks, cryptographic libraries, machine learning runtimes, and embedded firmware. In addition, [Atlas](https://github.com/nim-lang/atlas) is Nim's modern alternative workspace manager designed by the Nim core team for reproducible, monorepo, and lockfile-first environments.

Currently, **zero native support exists in Dependabot** (or Renovate) for Nim projects. Nim open-source maintainers and enterprise users must either manually track upstream releases, run ad-hoc scripts, or build bespoke CI pipelines to detect and bump dependency versions. Adding `nimble` to `dependabot-core` brings automated vulnerability remediation and routine dependency updates to the growing Nim community on GitHub.

---

## 2. Manifest & Lockfile Specifications

### A. Manifest Format (`*.nimble`)
Nimble manifest files (`<package_name>.nimble`) use Nim's declarative DSL syntax. Package metadata and dependencies are declared via top-level statements:

```nim
# Package metadata
version       = "1.2.0"
author        = "Jane Doe"
description   = "High-performance cryptographic hashing library"
license       = "MIT"
srcDir        = "src"

# Dependencies
requires "nim >= 2.0.0"
requires "checksums >= 0.1.0", "zippy >= 0.10.4"
requires "ws#head"
requires "react [gui] >= 1.0.0"
```

#### Key Characteristics:
1. **Dependency Syntax**: Declared using `requires "<package> <constraint>"`. Multiple comma-separated requirements can be combined on a single line or spanned across lines.
2. **Constraint Operators**: Supports standard comparison operators (`>=`, `<=`, `>`, `<`, `==`, `!=`), SemVer caret (`^=`), tilde (`~=`), and intersected ranges joined by `&` (e.g. `requires "pkg >= 1.0.0 & <= 1.5.0"`).
3. **VCS Pins**: Dependencies can be pinned to Git branches (`#head`, `#devel`) or commit SHAs (`#a1b2c3d`).
4. **Feature Flags**: Optional feature flags may be bracketed after the package name (e.g. `"pkg [gui] >= 1.0.0"`).

### B. Lockfile Format (`nimble.lock`)
Introduced in Nimble 0.14, `nimble.lock` is a deterministic, machine-readable JSON file specifying resolved dependency versions and commit revisions:

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

### C. Atlas Manifest & Lockfile (`atlas.config` / `atlas.lock`)
Atlas projects specify dependency targets in `atlas.config` and record exact resolved commit SHAs in `atlas.lock`:

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

## 3. Architecture & Dependabot Integration

Following the Dependabot Core architecture (`dependabot-core/NEW_ECOSYSTEMS.md`), the implementation will reside in `dependabot/nimble`:

```
dependabot-core/
└── nimble/
    ├── lib/
    │   └── dependabot/
    │       └── nimble/
    │           ├── file_fetcher.rb
    │           ├── file_parser.rb
    │           ├── update_checker.rb
    │           ├── file_updater.rb
    │           ├── metadata_finder.rb
    │           ├── package.rb
    │           └── version.rb
    └── spec/
        ├── fixtures/
        └── dependabot/nimble/
```

### Class Responsibilities:

### 1. `Dependabot::Nimble::FileFetcher`
- Discovers `*.nimble` manifests and companion lockfiles (`nimble.lock`, `atlas.lock`).
- Supports subdirectories and nested monorepo packages.
- Fetches `.tool-versions` or `.github/workflows/*.yml` if compiler synchronization is enabled.

### 2. `Dependabot::Nimble::FileParser`
- **Declarative AST Extraction**: Parses `requires` statements using a declarative lexer/parser without executing the `.nimble` file through a shell or compiler. This eliminates arbitrary code execution risks.
- Extracts package name, constraint string, constraint operator, VCS ref, and associated locked version.
- Associates lockfile entries from `nimble.lock` or `atlas.lock`.

### 3. `Dependabot::Nimble::UpdateChecker`
- Resolves the latest available releases:
  - **Registry Lookup**: Queries Nimble's official package directory (`packages.json`) to resolve package names to their canonical Git repository URLs.
  - **Git Tag Discovery**: Runs `git ls-remote --tags <url>` against the upstream repository to find SemVer release tags.
  - **Prerelease Filtering**: By default, stable tracks ignore prereleases (`alpha`, `beta`, `rc`, `devel`) unless the current version is already on a prerelease track.
- Evaluates SemVer version compatibility and determines whether an update satisfies existing bounds or requires a manifest constraint bump.
- Implements `requirements_to_unlock` (lockfile-only vs manifest+lockfile).

### 4. `Dependabot::Nimble::FileUpdater`
- **In-Place Formatting Preservation**: Modifies `*.nimble` files in-place while strictly preserving original indentation (2-space, 4-space, tabs), quotation marks (single vs double), comments, and multi-line formatting.
- **Transitive Lockfile Synchronization**:
  - For `nimble.lock`: Updates the target package version and commit SHA, and optionally delegates to `nimble lock <pkg>` to regenerate transitive dependency trees.
  - For `atlas.lock`: Updates pinned commit SHAs and version metadata.

### 5. `Dependabot::Nimble::MetadataFinder`
- Extracts repository URLs, release notes, and changelogs from upstream GitHub/GitLab releases or repository `CHANGELOG.md` files for display in Dependabot PR descriptions.

---

## 4. Cooldown Support

Dependabot's release cooldown mechanism prevents immediately updating to newly published releases to mitigate zero-day supply chain attacks.

- **Timestamp Source**: Upstream Git release tags contain commit timestamps (`commit.committer.date` or `tagger.date` via Git APIs or GitHub Releases API).
- **Evaluation**: `Dependabot::Nimble::UpdateChecker` extracts the release publication timestamp and compares it against the configured cooldown threshold (e.g. 7 days).

---

## 5. Security & Sandboxing Considerations

1. **Zero Untrusted Code Execution**:
   `.nimble` files can legally contain Nim task blocks (e.g. `task build, "build task": exec "rm -rf ..."`). Dependabot **must never execute `.nimble` files directly using the Nim compiler or shell**. All parsing is performed via declarative static text and regex scanning targeting only top-level `requires` and metadata assignments.
2. **Network Sandboxing**:
   All upstream queries are constrained to standard HTTPS git endpoints discovered in the official `packages.json` directory.
3. **Circular Dependency & ReDoS Immunity**:
   Version constraint parsing uses bounded regular expressions and linear interval matching to prevent catastrophic backtracking.

---

## 6. Implementation Plan & Milestones

### Phase 1: Core Implementation
- [ ] Scaffold `dependabot/nimble` using `rake ecosystem:create[nimble]`
- [ ] Implement `Dependabot::Nimble::Version` and `Requirement` (SemVer 2.0 with Caret, Tilde, and Range operators)
- [ ] Implement `FileFetcher` (`*.nimble`, `nimble.lock`, `atlas.config`, `atlas.lock`)
- [ ] Implement `FileParser` (Declarative AST parsing for `requires` statements)
- [ ] Implement `UpdateChecker` (Git tag discovery and `packages.json` resolution)
- [ ] Implement `FileUpdater` (In-place `.nimble` rewriter and lockfile updater)
- [ ] Implement `MetadataFinder` (GitHub/GitLab release notes & changelogs)

### Phase 2: Safety & Cooldown
- [ ] Implement release timestamp extraction for cooldown support
- [ ] Implement dangling dependency and cycle detection

### Phase 3: Testing & Quality Assurance
- [ ] Unit tests for all core classes (`spec/dependabot/nimble/*_spec.rb`)
- [ ] Real-world fixture verification against popular Nim packages:
  - `zippy` (complex multi-dependency manifest)
  - `yaml` (multi-line continuations and docstrings)
  - `cligen` (task blocks and CLI flags)
  - `nimble.lock` and `atlas.lock` real-world samples
- [ ] Local dry-run verification using `bin/dry-run.rb nimble <org/repo>`

### Phase 4: Beta Deployment
- [ ] Submit PR to `dependabot/dependabot-core`
- [ ] Enable ecosystem under Dependabot beta feature flag (`allow_beta_ecosystems?`)
- [ ] Community beta testing across popular Nim repositories on GitHub

### Phase 5: General Availability (GA)
- [ ] Address beta community feedback
- [ ] Remove beta restriction; enable globally on GitHub.com
- [ ] Update official GitHub Dependabot documentation

---

## 7. Technical Challenges & Mitigations

| Challenge | Mitigation |
| :--- | :--- |
| **`.nimble` files are Nim scripts** | Static declarative parser extracts only `requires` statements outside task blocks; never compiles or runs the Nim script. |
| **Preserving user indentation & comments** | In-place regex substitution preserves exact leading whitespace (spaces/tabs), trailing comments (`# ...`), and quote styles. |
| **Transitive dependencies in lockfiles** | Direct update of locked package entry combined with delegated solver invocation (`nimble lock`) in containerized helper when full transitive tree re-resolution is requested. |
| **Custom package URLs (`requires "https://..."`)** | Parser extracts direct Git URLs and queries remotes directly without requiring central registry resolution. |

---

## 8. Contributor Commitment

The authors and community maintainers commit to:
- Authoring the core Ruby implementation and test suites.
- Providing real-world test repositories and fixtures.
- Maintaining the `nimble` ecosystem during the beta period.
- Triaging issues and keeping pace with upstream Nimble and Atlas specification updates.

---

## 9. References & Prior Art

- [Nimble Specification](https://github.com/nim-lang/nimble#nimble-usage)
- [Nim Packages Registry (`packages.json`)](https://github.com/nim-lang/packages)
- [Atlas Package Manager](https://github.com/nim-lang/atlas)
- [Renimble Reference Implementation](https://github.com/elijahr/renimble) (Automated Nimble/Atlas updater and in-place rewriter)
- [Dependabot Core New Ecosystem Guide (`NEW_ECOSYSTEMS.md`)](https://github.com/dependabot/dependabot-core/blob/main/NEW_ECOSYSTEMS.md)
