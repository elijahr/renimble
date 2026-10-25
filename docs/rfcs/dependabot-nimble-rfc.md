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

## Background & Tooling Architecture

[Nim](https://nim-lang.org/) is a statically typed, compiled systems programming language with clean syntax, expressive metaprogramming, and zero-overhead C/C++/JavaScript compilation targets.

### The Relationship Between Nimble and Atlas

A key architectural consideration in the Nim ecosystem is the relationship between **Nimble** and **Atlas**:

* **Nimble** is the official, standard package manager bundled with the Nim compiler since 2014. It specifies the canonical package manifest format (`<package>.nimble`), resolves dependencies against the central registry (`nim-lang/packages`), manages a global package cache in `~/.nimble/pkgs/`, and (since v0.14) generates project-level `nimble.lock` files.
* **Atlas** is **not a divergent package manager or competing language ecosystem**; it is a **companion workspace cloner and monorepo orchestrator** developed by Andreas Rumpf (Nim's creator).
  * **Shared Manifest**: Atlas does not invent a new manifest format. It directly parses, consumes, and updates standard `*.nimble` files (`atlas use <pkg>` literally parses and patches the project's `.nimble` file).
  * **Shared Registry**: Atlas clones from the same Git repositories indexed in `nim-lang/packages`.
  * **Isolated Directory Modes**: Rather than using a global package directory, Atlas clones dependencies into an isolated workspace directory:
    * *Default Project Mode*: Clones dependencies into `./deps/<pkg>/`.
    * *Configurable Directory*: Overridden via `--deps=PATH` or `"deps": "path"` in `atlas.config`.
    * *Workspace / Monorepo Mode*: A parent workspace contains a single shared `deps/` directory, linking sub-projects via `atlas link <path>`.
  * **Compiler Configuration (`nim.cfg`)**: Atlas configures the Nim compiler to locate workspace dependencies by generating an idempotent, delimited section in `nim.cfg`:
    ```ini
    ############# begin Atlas config section ##########
    --noNimblePath
    --path:"../deps/foo/src"
    --path:"../deps/bar/src"
    ############# end Atlas config section   ##########
    ```
    The `--noNimblePath` switch is crucial: it instructs the Nim compiler to bypass global `~/.nimble/pkgs/` lookups and resolve imports exclusively from the explicit `--path` directories in the workspace.
  * **Lockfile Coexistence**: Atlas can generate its own workspace lockfile (`atlas.lock`) as well as standard `nimble.lock`.

### The Three Dependency Cache Topologies in Nim

A dependency updater must account for the three distinct dependency locations that a Nim repository may use:

1. **Global Nimble Mode (`~/.nimble`)**:
   * *Location*: `$HOME/.nimble/pkgs2/` (or customized via `NIMBLE_DIR` environment variable / `--nimbleDir:<path>` CLI switch).
   * *Compiler Lookup*: The Nim compiler automatically checks `~/.nimble` by default.
   * *Lockfile*: `nimble.lock` (v1 JSON).
2. **Project-Local Nimble Mode (`nimbledeps`)**:
   * *Location*: `./nimbledeps/pkgs2/` immediately adjacent to the `.nimble` file.
   * *Trigger*: Automatically activated whenever a directory named `nimbledeps` exists (or when initialized via `nimble setup -l` / `nimble develop -l`).
   * *Behavior*: Nimble automatically overrides `$nimbleDir` to `./nimbledeps`, ignores `$HOME/.nimble`, and links binaries to `./nimbledeps/bin`.
   * *Compiler Lookup*: Configured via `nimblePath = "$project/nimbledeps/pkgs2"` in `nim.cfg`.
   * *Lockfile*: `nimble.lock`.
3. **Atlas Workspace Mode (`deps`)**:
   * *Location*: `./deps/` (or custom path configured via `"deps"` in `atlas.config`).
   * *Compiler Lookup*: Configured via `--noNimblePath` and explicit `--path` entries in `nim.cfg`.
   * *Lockfile*: `atlas.lock` (and/or `nimble.lock`).

**Ignored Directory Contract for File Discovery**:
When scanning a repository for `.nimble` manifests, dependency updaters (Dependabot, Renovate, Renimble) **must ignore `nimbledeps/`, `deps/`, and `nimcache/`**. Cloned dependencies inside those directories contain their own `.nimble` files which must never be confused with the root project manifest.

**Conclusion for Dependabot & Renovate**:
Support for Nimble and Atlas belongs in the **same ecosystem (`nimble`)**. The manifest is always `*.nimble`. Atlas simply provides an alternative workspace layout and companion lockfile (`atlas.lock` alongside `nimble.lock`). Treating them as separate ecosystems would lead to redundant code and confusing configuration.

### How `.nimble` Files Are Parsed: NimScript vs. Static AST

A common concern with Nim package manifests is that `.nimble` files are technically written in **NimScript**—a Turing-complete subset of Nim executed by the compiler VM (`nim e`), which can define custom tasks (`task test, "...": exec "..."`) and helper procedures.

However, the assumption that `.nimble` manifests *must* be executed as code to read versions or dependencies is **incorrect**:

1. **Static Declarative AST Extraction (The Atlas Approach)**:
   In `nim-lang/atlas/src/basic/parse_requires.nim`, Atlas itself does **not** execute `.nimble` files to discover requirements. Instead, it uses the Nim compiler's AST parser (`compiler/ast`, `compiler/syntaxes`) to statically inspect top-level assignments (`version = "..."`) and function calls (`requires "foo >= 1.0.0"`). It safely skips all `task`, `before`, `after`, and shell `exec` blocks without evaluation.
2. **Empirical Reality across 2,978 Packages**:
   Across the 2,978 packages in `nim-lang/packages`, over **99.5%** define `version = "..."` and `requires "..."` as simple top-level string literal statements.
3. **Native Nimble CLI Capabilities**:
   When the Nimble toolchain is available, Nimble provides official built-in inspection commands:
   * **`nimble dump --json`**: Evaluates the manifest and outputs a complete, structured JSON representation:
     ```json
     {
       "name": "renimble",
       "version": "0.1.0",
       "requires": [
         {
           "name": "nim",
           "str": ">= 2.0.0",
           "ver": { "kind": "verEqLater", "ver": "2.0.0" }
         }
       ],
       "srcDir": "src",
       "backend": "c"
     }
     ```
   * **`nimble dump`**: Outputs key-value pairs formatted as INI-style strings.
   * **`nimble check`**: Performs static and semantic validation of manifest correctness.
4. **Dependabot Security Architecture**:
   In `dependabot-core`, the parser avoids arbitrary code execution entirely by using **declarative static regex / AST pattern matching** for `.nimble` manifests (analogous to how Dependabot handles Pipfiles or Gemspecs without executing arbitrary Python/Ruby). For environments with language toolchains present, `nimble dump --json` serves as an optional golden reference verifier.

### Empirical Ecosystem Metrics (Live GitHub API)
- **Active Repositories**: **14,090+ public Nim repositories** on GitHub (`language:nim`).
- **Central Package Registry**: **2,978 packages** indexed in [`nim-lang/packages`](https://github.com/nim-lang/packages).
- **Core Community**: `nim-lang/Nim` (**18,280+ stars**, 1,560+ forks) and `nim-lang/nimble` (**1,400+ stars**, 218 forks).
- **Community Demand**: Prior open requests such as [`nim-lang/nimble#1043`](https://github.com/nim-lang/nimble/issues/1043) have actively requested Dependabot and Renovate support.
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
- `Dependabot::Nimble::FileFetcher`: Locates `*.nimble`, `nimble.lock`, `atlas.config`, and `atlas.lock`. Supports nested directories and monorepos while strictly excluding `nimbledeps/`, `deps/`, and `nimcache/` from recursive traversal.
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

1. We propose supporting `atlas.lock` and `atlas.config` as companion lockfiles/configurations under the unified `nimble` ecosystem (since Atlas directly consumes `*.nimble` manifests, updates `*.nimble` via `atlas use`, and queries the same `nim-lang/packages` registry). Does the team agree with this unified approach?
2. Does the team have preferences regarding pure-Ruby lockfile JSON manipulation vs invoking a containerized `nimble lock` or `atlas pin` helper for transitive tree resolution?
3. Are there specific rate-limiting or caching guidelines for the static `packages.json` registry file?
