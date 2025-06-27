# GutenbergKit Release Process

At this time, the GutenbergKit release process is fairly manual. In the future, we will automate this process with CI tasks.

1. Switch to the `trunk` branch.
1. Increment the version without tagging[^1]: `npm --no-git-tag-version version [patch|minor|major]`
1. Create a new build for iOS[^2]: `make build`
1. Add the changes: `git add .`
1. Commit the changes: `git commit -m "X.X.X"`
1. Create a tag: `git tag vX.X.X`
1. Push the changes: `git push origin trunk --tags`
1. Create a new release on GitHub: `gh release create vX.X.X --generate-notes --title "X.X.X"`

After the release is created, it is ready for integration into the WordPress app.

[^1]: We increment the version before building and without tagging so that (1) the correct version number is included in the build's [error reporting metadata](https://github.com/wordpress-mobile/GutenbergKit/blob/8195901ec8883125dcfa102abf2b6a2a3962af3e/src/utils/exception-parser.js#L99) and (2) the Git tag includes the latest build output.
[^2]: CI tasks create new Android builds for each commit. However, such infrastructure is not yet in place for iOS. Therefore, we must manually create and commit the iOS build.
