# GutenbergKit Release Process

Use the provided release script to automate the entire process:

```bash
# For a patch release (0.3.0 -> 0.3.1)
make release VERSION_TYPE=patch

# For a minor release (0.3.0 -> 0.4.0)
make release VERSION_TYPE=minor

# For a major release (0.3.0 -> 1.0.0)
make release VERSION_TYPE=major

# Test the release process without making changes
make release VERSION_TYPE=patch DRY_RUN=true
```

The script:

1. Verifies you're on the `trunk` branch
1. Checks that your working directory is clean
1. Ensures required dependencies are installed
1. Increments the version number[^1]
1. Builds the project[^2]
1. Commits changes
1. Creates a Git tag
1. Pushes to `origin/trunk` with tags
1. Creates a GitHub release
1. Creates a new release on GitHub: `gh release create vX.X.X --generate-notes --title "X.X.X"`

After the release is created, it is ready for integration into the WordPress app.

[^1]: We increment the version before building and without tagging so that (1) the correct version number is included in the build's [error reporting metadata](https://github.com/wordpress-mobile/GutenbergKit/blob/8195901ec8883125dcfa102abf2b6a2a3962af3e/src/utils/exception-parser.js#L99) and (2) the Git tag includes the latest build output.
[^2]: CI tasks create new Android builds for each commit. However, such infrastructure is not yet in place for iOS. Therefore, we must manually create and commit the iOS build.
