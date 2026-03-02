# WordPress App Integration

This guide covers how to integrate GutenbergKit into the WordPress mobile apps. WordPress-iOS and WordPress-Android are the primary consumers of GutenbergKit.

**Related repositories:**

-   [WordPress-iOS](https://github.com/wordpress-mobile/WordPress-iOS)
-   [WordPress-Android](https://github.com/wordpress-mobile/WordPress-Android)

## Integration Methods

GutenbergKit can be integrated using different methods depending on your development workflow. Choose the method that best fits your current needs.

### Local Development

**Use case**: Simultaneous development on both GutenbergKit and a WordPress app.

This method is ideal when you're actively making changes to GutenbergKit and need to see them immediately in the WordPress app.

#### iOS (Swift Package Manager)

In your `Package.swift` dependencies array, use a local path reference:

```swift
.package(path: "../GutenbergKit")
```

Make sure the path points to your local GutenbergKit clone relative to your WordPress-iOS project.

#### Android (Gradle)

1. Copy `local-builds.gradle-example` to `local-builds.gradle`
2. Uncomment the `localGutenbergKitPath` line and set it to your local GutenbergKit path:
    ```groovy
    localGutenbergKitPath = "../GutenbergKit"
    ```
3. Run Gradle sync — this substitutes the Maven dependency with the local project

### Git Revision

**Use case**: Testing specific GutenbergKit commits before any release.

This method is useful for testing pull requests or in-progress work that hasn't been released yet.

#### iOS

Use a `revision` dependency in `Package.swift`:

```swift
.package(url: "https://github.com/wordpress-mobile/GutenbergKit", revision: "<commit-hash>")
```

**Important**: When using a revision dependency, the JavaScript build output must be committed to that revision. Run `make build` in GutenbergKit and commit the changes before referencing the commit hash. This is required until CI infrastructure is in place to automate JavaScript builds.

#### Android

In `gradle/libs.versions.toml`, use the PR number and commit hash format:

```toml
gutenberg-kit = '<PR-number>-<commit-hash>'
```

For example:

```toml
gutenberg-kit = '283-3110b008df0edceac04a1c6f18724476ce67b3ce'
```

CI (Buildkite) publishes builds for PRs to the Maven repository automatically.

### Pre-releases

**Use case**: Integrating GutenbergKit work into WordPress app trunk before a formal release.

Pre-releases create alpha version tags without creating a GitHub Release. They're useful for getting changes into the WordPress apps' main branches early.

#### Creating a Pre-release

From the GutenbergKit repository:

```bash
make release VERSION_TYPE=prepatch  # 0.13.2 -> 0.13.3-alpha.0
```

Available version types:

-   `prepatch` — increments patch and adds alpha suffix (0.13.2 → 0.13.3-alpha.0)
-   `preminor` — increments minor and adds alpha suffix (0.13.2 → 0.14.0-alpha.0)
-   `premajor` — increments major and adds alpha suffix (0.13.2 → 1.0.0-alpha.0)
-   `prerelease` — increments the alpha number (0.13.3-alpha.0 → 0.13.3-alpha.1)

This pushes a git tag (e.g., `v0.13.3-alpha.0`) and CI publishes the Android build to the Maven repository.

#### iOS

Use an `exact` version in `Package.swift`:

```swift
.package(url: "https://github.com/wordpress-mobile/GutenbergKit", exact: "0.13.3-alpha.0")
```

#### Android

In `gradle/libs.versions.toml`:

```toml
gutenberg-kit = '0.13.3-alpha.0'
```

### Formal Releases

**Use case**: Stable releases with grouped changes for production.

Formal releases create a GitHub Release with auto-generated release notes and are used for WordPress app releases.

#### Creating a Formal Release

From the GutenbergKit repository:

```bash
make release VERSION_TYPE=patch  # 0.13.2 -> 0.13.3
```

Available version types:

-   `patch` — bug fixes and minor changes (0.13.2 → 0.13.3)
-   `minor` — new features, backwards compatible (0.13.2 → 0.14.0)
-   `major` — breaking changes (0.13.2 → 1.0.0)

This creates a GitHub Release with auto-generated notes and CI publishes the Android build to the Maven repository.

#### iOS

Use a `from` version in `Package.swift`:

```swift
.package(url: "https://github.com/wordpress-mobile/GutenbergKit", from: "0.13.3")
```

#### Android

In `gradle/libs.versions.toml`:

```toml
gutenberg-kit = '0.13.3'
```

## Workflow Recommendations

| Scenario                       | Recommended Method |
| ------------------------------ | ------------------ |
| Active feature development     | Local Development  |
| PR review / testing            | Git Revision       |
| Merging to WordPress app trunk | Pre-release        |
| WordPress app release          | Formal Release     |

## Platform-Specific Notes

### iOS

-   `Package.swift` is at the repository root (not in the `ios/` directory)
-   Use `revision` for commit hashes, `exact` for pre-release tags, `from` for stable releases
-   JavaScript build output must be committed when using revision dependencies

### Android

-   CI (Buildkite) publishes builds to the Maven repository
-   PR builds use `<PR-number>-<commit-hash>` format
-   Local development uses Gradle's `includeBuild` with dependency substitution
