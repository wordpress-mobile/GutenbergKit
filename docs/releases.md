# GutenbergKit Release Process

## How publishing works

Every push to `trunk` publishes both platforms automatically:

-   **Android**: the `:android: Publish Android Library` step pushes a Maven artifact keyed by the commit (consumable via Git revision pins).
-   **iOS**: the `:s3: Publish XCFramework to S3` step uploads the signed XCFramework under `gutenbergkit/<commit-sha>/`, and `Publish PR XCFramework` does the same on PR builds under a `pr-build/<n>` snapshot branch.

A **tagged release** is a separate, manually-triggered publish flow on top of that: it produces a stable `vX.Y.Z` tag whose `Package.swift` points at the prebuilt XCFramework on CDN, plus a GitHub Release with the XCFramework attached. SPM consumers pin the tag; everything else can pin a commit/branch.

The tagged release happens in two steps: a local script bumps the version on `trunk`, then a CI build creates the tag and the GitHub release.

## Step 1 — Bump versions on trunk

Run the release script:

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
1. Builds the project[^2]
1. Commits the version bump as `chore(release): X.Y.Z`
1. Pushes to `origin/trunk`

It does **not** create the git tag or the GitHub release — that's Step 2.

## Step 2 — Publish via Buildkite

Step 1 prints the SHA of the version-bump commit it just pushed. Trigger a new Buildkite build with that SHA pinned:

1. Open <https://buildkite.com/automattic/gutenbergkit/builds/new>
2. **Branch**: `trunk`
3. **Commit**: the SHA printed by Step 1
4. **Environment Variables**: `NEW_VERSION=vX.Y.Z`

Pinning the commit matters — if you leave it blank, Buildkite resolves `trunk` to HEAD at trigger time, and a concurrent merge would tag the wrong commit.

The build runs a `:white_check_mark: Validate Swift release` step early on (gated on `NEW_VERSION`) that fast-fails if the tag name is malformed, or if the tag or GitHub Release already exists. After that, the `:rocket: Publish Swift release` step:

1. Rewrites `Package.swift` to consume the binary target via `.release(version:, checksum:)`
1. Uploads the XCFramework to `s3://a8c-apps-public-artifacts/gutenbergkit/vX.Y.Z/`
1. Commits the rewrite on a `release-staging/vX.Y.Z` branch, pushes it to origin
1. Creates the GitHub Release **as a draft**, uploading the XCFramework + checksum as assets — at this point no tag exists yet
1. Flips the release out of draft state, which atomically creates the `vX.Y.Z` tag pointing at the staging-branch commit
1. Deletes the staging branch (best-effort)

The two-phase publish means the tag is the last thing created. If anything fails before the draft is flipped — S3 upload, asset upload, staging push — no tag exists and consumers see nothing.

The tag's commit lives off `trunk`'s history (parented on `trunk` but only reachable via the tag), so SPM consumers pinning `vX.Y.Z` resolve a `Package.swift` that fetches the prebuilt XCFramework from CDN rather than rebuilding from local sources.

### Recovering from a partial publish

The flow is designed so that the tag's existence is the only signal of completion: if `vX.Y.Z` exists, the release is real.

If the build fails before the draft-flip step, no tag was created and no consumer can resolve `vX.Y.Z`. Re-run Step 2 with the same `NEW_VERSION` once the underlying issue is fixed — `validate` will pass (no tag, no release), and S3 uploads are idempotent (`if_exists: :replace`). You may need to manually delete the leftover draft release in the GitHub UI before re-running.

If the build fails specifically on the cleanup step (`git push origin --delete release-staging/vX.Y.Z`), the release is fine — the tag exists and is valid — but the staging branch is left behind. Delete it manually with `git push origin --delete release-staging/vX.Y.Z`.

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
