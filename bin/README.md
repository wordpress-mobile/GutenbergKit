# Bin Directory

This directory contains utility scripts for the GutenbergKit project.

## Scripts

### `release.sh`

Automates the GutenbergKit release process. This script performs all the steps outlined in the [release documentation](../docs/releases.md).

#### Usage

```bash
# Direct usage
./bin/release.sh [patch|minor|major] [--dry-run]

# Via Makefile (recommended)
make release VERSION_TYPE=[patch|minor|major] [DRY_RUN=true]
```

#### Examples

```bash
# Create a patch release
make release VERSION_TYPE=patch

# Create a minor release
make release VERSION_TYPE=minor

# Create a major release
make release VERSION_TYPE=major

# Test the release process without making changes
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
# Direct usage
node bin/prep-translations.js

# Via npm script
npm run prep-translations
```
