# Bin Directory

This directory contains utility scripts for the GutenbergKit project.

## Scripts

### `release.sh`

Automates the GutenbergKit release process. This script performs all the steps outlined in the [release documentation](../docs/releases.md).

#### Usage

```bash
# Direct usage
./bin/release.sh [<newversion> | major | minor | patch | premajor | preminor | prepatch | prerelease] [--dry-run]

# Via Makefile (recommended)
make release VERSION_TYPE=[<newversion> | major | minor | patch | premajor | preminor | prepatch | prerelease] [DRY_RUN=true]
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

# Test without making changes
make release VERSION_TYPE=patch DRY_RUN=true
```

#### What it does

1. **Pre-flight checks:**

    - Verifies you're on the `trunk` branch
    - Checks that your working directory is clean
    - Ensures required dependencies are installed (`npm`, `make`)
    - Verifies the new version's tag does not already exist on origin

2. **Release process:**
    - Sets the new version in `package.json` and `package-lock.json`
    - Builds the project using `make build`, which also regenerates the native version files
    - Commits all changes as `chore(release): X.Y.Z`
    - Pushes the commit to `origin/trunk`
    - Prints the steps to trigger the Buildkite publish build, which creates the tag and the GitHub release (see the [release documentation](../docs/releases.md))

#### Dependencies

-   `npm` - for version management and building
-   npm packages installed (e.g., `npm ci`) - the script calculates versions with the project's `semver`
-   `make` - for building the project
-   Git - for version control operations

### `demo-app-login.sh`

Signs a demo app into WordPress sites with credentials stored on your machine: the self-hosted sites listed in `~/.config/wp/sites`, and a WordPress.com site with the bearer token in `WPCOM_TOKEN` or `~/.wpcom-token`. See [Signing In to the Demo Apps](../docs/code/demo-app-login.md).

#### Usage

```bash
make login-ios-app
make login-android-app
```

### `fetch-translations.js`

Fetches and caches locale string files for the GutenbergKit project. This script is typically run as part of the build process.

#### Usage

```bash
make fetch-translations
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
