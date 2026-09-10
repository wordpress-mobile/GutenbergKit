# Bin Directory

This directory contains utility scripts for the GutenbergKit project.

## Scripts

### `release.sh`

Automates the GutenbergKit release process. This script performs all the steps outlined in the [release documentation](../docs/releases.md).

#### Usage

```bash
# Direct usage
./bin/release.sh [<newversion> | major | minor | patch | premajor | preminor | prepatch | prerelease | from-git] [--dry-run]

# Via Makefile (recommended)
make release VERSION_TYPE=[<newversion> | major | minor | patch | premajor | preminor | prepatch | prerelease | from-git] [DRY_RUN=true]
```

#### Version Types

| Type           | Description                     | Example                           |
| -------------- | ------------------------------- | --------------------------------- |
| `major`        | Increment major version         | `1.2.3` → `2.0.0`                 |
| `minor`        | Increment minor version         | `1.2.3` → `1.3.0`                 |
| `patch`        | Increment patch version         | `1.2.3` → `1.2.4`                 |
| `premajor`     | Increment major with prerelease | `1.2.3` → `2.0.0-alpha.0`         |
| `preminor`     | Increment minor with prerelease | `1.2.3` → `1.3.0-alpha.0`         |
| `prepatch`     | Increment patch with prerelease | `1.2.3` → `1.2.4-alpha.0`         |
| `prerelease`   | Increment prerelease version    | `1.2.3-alpha.0` → `1.2.3-alpha.1` |
| `from-git`     | Use version from git tag        | Uses latest git tag               |
| `<newversion>` | Set specific version            | `1.2.3` → `1.2.3`                 |

#### Examples

```bash
# Standard releases
make release VERSION_TYPE=patch
make release VERSION_TYPE=minor
make release VERSION_TYPE=major

# Custom version
make release VERSION_TYPE=1.2.3

# Prerelease versions
make release VERSION_TYPE=premajor
make release VERSION_TYPE=preminor
make release VERSION_TYPE=prepatch
make release VERSION_TYPE=prerelease

# Use version from git tag
make release VERSION_TYPE=from-git

# Test without making changes
make release VERSION_TYPE=patch DRY_RUN=true
```

#### What it does

1. **Pre-flight checks:**

    - Verifies you're on the `trunk` branch
    - Checks that your working directory is clean
    - Ensures required dependencies are installed (`gh`, `npm`, `make`)

2. **Release process:**
    - Increments the version number in `package.json`
    - Builds the project using `make build`
    - Commits all changes with the version number as the commit message
    - Creates a git tag with the version number
    - Pushes changes to `origin/trunk` with tags
    - Creates a GitHub release with auto-generated notes

#### Dependencies

-   `gh` (GitHub CLI) - for creating GitHub releases
-   `npm` - for version management and building
-   `make` - for building the project
-   Git - for version control operations

### `prep-translations.js`

Prepares translations for the GutenbergKit project. This script is typically run as part of the build process.

#### Usage

```bash
make prep-translations
```

### `check-wordpress-package-duplicates.js`

Fails when any `@wordpress` package is installed more than once in the production dependency graph. The editor exposes these packages on `window.wp` for plugin scripts, which only works when each package is a single module instance. A nested second copy brings its own React contexts, data stores, and private APIs, and nothing at runtime reports the split.

The check reads `package-lock.json` rather than the installed tree, so it describes what a fresh `npm ci` produces, requires no `node_modules`, and counts separate installs rather than distinct versions — two copies of the same version are still two module instances.

Packages listed in the script's `KNOWN_DUPLICATES` are reported as warnings instead of failures. Each entry should be removed once the underlying version mismatch is resolved, typically by bumping the `@wordpress` packages together; an entry that no longer applies fails the check rather than lingering to mask a future regression.

An entry is a deliberate exception rather than a fix, and is warranted when the coordinated bump genuinely has to wait — a security advisory that moves one package alone, for instance. The cost is that the editor ships a known split: for a package holding a store, context, or registry, plugin scripts receive a different instance than the editor's own components, with nothing at runtime to signal it. Record the follow-up work alongside the entry.

#### Usage

```bash
make check-wp-packages
```
