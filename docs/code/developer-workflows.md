# Developer Workflows

This guide covers commit conventions, pull request guidelines, and labeling workflows in GutenbergKit.

## Commit Messages

This project follows the [Conventional Commits](https://www.conventionalcommits.org/) specification for commit messages and pull request titles.

Format: `<type>[optional scope][optional !]: <description>`

To signal a **breaking change**, append `!` after the type (and scope, if present):

```
feat!: remove deprecated editor bridge method
fix(api)!: change block serialization format
```

Common types:

| Type       | When to use                                |
| ---------- | ------------------------------------------ |
| `feat`     | New feature or capability                  |
| `fix`      | Bug fix                                    |
| `perf`     | Performance improvement                    |
| `test`     | Adding or updating tests                   |
| `docs`     | Documentation changes                      |
| `build`    | Build system or dependency changes         |
| `ci`       | CI/CD configuration changes                |
| `refactor` | Code restructuring without behavior change |
| `chore`    | Routine maintenance tasks                  |

Examples: `feat: add offline indicator`, `fix: resolve iOS retain cycle in async flow`

## Pull Requests

When creating a pull request:

1. **Use the PR template**: The template in `.github/PULL_REQUEST_TEMPLATE.md` provides the required structure.
2. **Assign a label**: Use `gh label list` to see available labels and select the most relevant one.
3. **Follow Conventional Commits**: The PR title should use the same format as commit messages above.
4. **Update the changelog**: If your PR contains user-facing changes, add an entry to the appropriate section under `## Trunk` in `CHANGELOG.md`. Breaking changes are especially important to capture.

### Automatic Labeling

PRs are automatically labeled based on the Conventional Commits prefix in the title:

| Prefix                               | Label applied                    |
| ------------------------------------ | -------------------------------- |
| `feat`                               | `[Type] Enhancement`             |
| `fix`                                | `[Type] Bug`                     |
| `perf`                               | `[Type] Performance`             |
| `test`                               | `[Type] Automated Testing`       |
| `docs`                               | `[Type] Developer Documentation` |
| `build`, `ci`                        | `[Type] Build Tooling`           |
| `refactor`, `task`, `chore`, `style` | `[Type] Task`                    |
| any type with `!`                    | `[Type] Breaking Change`         |

If you manually apply a type label before the automation runs, your choice is respected — the workflow skips re-labeling when a conflicting type label is already present.
