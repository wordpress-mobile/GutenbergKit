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

1. Open <https://buildkite.com/organizations/automattic/pipelines/gutenbergkit/builds/new>
2. **Branch**: `trunk`
3. **Commit**: the SHA printed by Step 1
4. **Environment Variables**: `NEW_VERSION=vX.Y.Z`

Pinning the commit matters — if you leave it blank, Buildkite resolves `trunk` to HEAD at trigger time, and a concurrent merge would tag the wrong commit.

The build runs a `:white_check_mark: Validate Swift release` step early on (gated on `NEW_VERSION`) that fast-fails if the tag name is malformed, if the tag or GitHub Release already exists, or if no previous release tag can be resolved to generate notes against. It logs the tag the notes will be based on, so a wrong base surfaces before anything is published. After that, the `:rocket: Publish Swift release` step:

1. Rewrites `Package.swift` to consume the binary target via `.release(version:, checksum:)`
1. Uploads the XCFramework to `s3://a8c-apps-public-artifacts/gutenbergkit/vX.Y.Z/`
1. Commits the rewrite on a local `release/vX.Y.Z` branch (never pushed to origin), tags `vX.Y.Z`, and pushes **only the tag** — `git push <tag>` carries the commit along with the tag ref, so the commit becomes reachable on origin via the tag alone
1. Generates release notes against the previous stable release tag (see [Release Notes](#release-notes))
1. Creates the GitHub Release against the now-existing tag, uploading the XCFramework + checksum as assets (adds `--prerelease` when the version contains `-`)

The tag is pushed before the GitHub Release is created. Once the tag is on origin, SPM consumers pinning `vX.Y.Z` can resolve a `Package.swift` that fetches the prebuilt XCFramework from CDN — the GH Release is metadata and an asset mirror on top of that.

The tag's commit lives off `trunk`'s history (parented on `trunk` but only reachable via the tag ref), matching the `pr-build/<n>` snapshot-branch shape but published under a tag instead of a branch. One consequence: release tags are not reachable from one another, so GitHub cannot infer which tag to generate release notes against and the release lane must pass one explicitly. See [Release Notes](#release-notes).

### Recovering from a partial publish

If the build fails before the tag is pushed (validate, Package.swift rewrite, S3 upload, or local commit/tag), no tag exists and no consumer can resolve `vX.Y.Z`. Re-run Step 2 with the same `NEW_VERSION` once the underlying issue is fixed — `validate` will pass (no tag, no release), and S3 uploads are idempotent (`if_exists: :replace`).

If the build fails specifically on `gh release create` (tag pushed, but GH Release missing), the tag is the source of truth: SPM consumers resolving `vX.Y.Z` already work. To create the missing Release page, run the following manually against the existing tag — re-running the full Buildkite step would fail at `validate` because the tag now exists.

```bash
gh release create vX.Y.Z \
    --title vX.Y.Z \
    --generate-notes \
    --notes-start-tag vPREVIOUS \
    [--prerelease] \
    <xcframework.zip> <checksum.txt>
```

`--notes-start-tag` is required, and `vPREVIOUS` must be the previous **stable** release (skip any intervening prereleases). Omitting it silently restates every release back to `v0.16.0` — see [Release Notes](#release-notes).

## Release Notes

GitHub generates the release notes, but the release lane tells it explicitly which tag to generate them against — it does not let GitHub infer the base.

GitHub's inference picks the most recent tag whose commit is an **ancestor** of the one being released. Our release tags never satisfy that: each one points at a `Package.swift` rewrite committed on a local `release/vX.Y.Z` branch that is never pushed, so no release tag is reachable from any other. Left to infer, GitHub falls back to the last tag that does sit on `trunk` — `v0.16.0` — and restates every PR merged since. So `previous_release_tag` in the `Fastfile` resolves the base instead:

-   The most recent **stable** release older than the version being published
-   Prereleases are skipped as candidates, matching GitHub's default. A stable release therefore reports everything since the last stable release, including work already listed in its own alphas
-   If no such release exists, the lane fails rather than publishing notes that might restate old releases

Notes are organized into the following categories based on PR labels:

-   **Breaking Changes** — `[Type] Breaking Change`
-   **Features & Enhancements** — `[Type] Enhancement`
-   **Bug Fixes** — `[Type] Bug`, `[Type] Regression`
-   **Other Changes** — everything else (excludes `[Type] Automated Testing`, `[Type] Build Tooling`, `[Type] Task`, `[Type] Developer Documentation`, and `dependencies`)

Dependabot dependency bump PRs are excluded automatically.

PRs are labeled automatically based on their Conventional Commits title prefix. See the [Developer Workflows](./code/developer-workflows.md) guide for details on the labeling rules.

[^1]: We increment the version before building and without tagging so that (1) the correct version number is included in the build's [error reporting metadata](https://github.com/wordpress-mobile/GutenbergKit/blob/8195901ec8883125dcfa102abf2b6a2a3962af3e/src/utils/exception-parser.js#L99) and (2) the Git tag includes the latest build output.
[^2]: CI tasks create new Android builds for each commit. However, such infrastructure is not yet in place for iOS. Therefore, we must manually create and commit the iOS build.
