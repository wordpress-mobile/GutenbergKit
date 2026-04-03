# GutenbergKit Release Process

Use the provided release script to automate the entire process:

```bash
# Standard version increments
make release VERSION_TYPE=patch    # 0.3.0 -> 0.3.1
make release VERSION_TYPE=minor    # 0.3.0 -> 0.4.0
make release VERSION_TYPE=major    # 0.3.0 -> 1.0.0

# Custom version number
make release VERSION_TYPE=1.2.3

# Prerelease versions (using alpha identifier)
make release VERSION_TYPE=premajor  # 0.3.0 -> 1.0.0-alpha.0
make release VERSION_TYPE=preminor  # 0.3.0 -> 0.4.0-alpha.0
make release VERSION_TYPE=prepatch  # 0.3.0 -> 0.3.1-alpha.0
make release VERSION_TYPE=prerelease # 1.2.3-alpha.0 -> 1.2.3-alpha.1

# Use version from git tag
make release VERSION_TYPE=from-git

# Test the release process without making changes
make release VERSION_TYPE=patch DRY_RUN=true
```

The script:

1. Verifies you're on the `trunk` branch
1. Checks that your working directory is clean
1. Ensures required dependencies are installed
1. Increments the version number[^1]
1. Updates `CHANGELOG.md` — moves the Trunk section to the new version and creates a fresh Trunk section
1. Builds the project[^2]
1. Commits changes
1. Creates a Git tag
1. Pushes to `origin/trunk` with tags
1. Creates a GitHub release: `gh release create vX.X.X --generate-notes --title "X.X.X"`

After the release is created, it is ready for integration into the WordPress app.

## Changelog

The project maintains a `CHANGELOG.md` file at the repository root. It uses a **Trunk** section at the top where unreleased changes are staged under four categories:

-   **Breaking Changes** — API removals, behavior changes, platform requirement increases
-   **New Features** — new capabilities
-   **Bug Fixes** — bug fixes
-   **Internal Changes** — refactors, tooling, tests, docs

When you merge a PR that contains user-facing changes, add an entry to the appropriate section in Trunk. Breaking changes are especially important to capture — they help consumers of the library plan upgrades.

During a release, the script automatically renames the Trunk section to the new version number and creates a fresh empty Trunk section.

## Release Notes

GitHub automatically generates release notes when a release is created. Notes are organized into the following categories based on PR labels:

-   **Breaking Changes** — `[Type] Breaking Change`
-   **Features & Enhancements** — `[Type] Enhancement`
-   **Bug Fixes** — `[Type] Bug`, `[Type] Regression`
-   **Other Changes** — everything else (excludes `[Type] Automated Testing`, `[Type] Build Tooling`, `[Type] Task`, `[Type] Developer Documentation`, and `dependencies`)

Dependabot dependency bump PRs are excluded automatically.

PRs are labeled automatically based on their Conventional Commits title prefix. See the [Developer Workflows](./code/developer-workflows.md) guide for details on the labeling rules.

[^1]: We increment the version before building and without tagging so that (1) the correct version number is included in the build's [error reporting metadata](https://github.com/wordpress-mobile/GutenbergKit/blob/8195901ec8883125dcfa102abf2b6a2a3962af3e/src/utils/exception-parser.js#L99) and (2) the Git tag includes the latest build output.
[^2]: CI tasks create new Android builds for each commit. However, such infrastructure is not yet in place for iOS. Therefore, we must manually create and commit the iOS build.
