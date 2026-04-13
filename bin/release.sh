#!/bin/bash

# GutenbergKit Release Script
# This script automates the release process for GutenbergKit

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [<newversion> | major | minor | patch | premajor | preminor | prepatch | prerelease | from-git] [--dry-run]"
    echo ""
    echo "Arguments:"
    echo "  <newversion>      Custom version number (e.g., 1.2.3)"
    echo "  major            Increment major version (1.0.0 -> 2.0.0)"
    echo "  minor            Increment minor version (1.2.0 -> 1.3.0)"
    echo "  patch            Increment patch version (1.2.3 -> 1.2.4)"
    echo "  premajor         Increment major version and add prerelease (1.2.3 -> 2.0.0-alpha.0)"
    echo "  preminor         Increment minor version and add prerelease (1.2.3 -> 1.3.0-alpha.0)"
    echo "  prepatch         Increment patch version and add prerelease (1.2.3 -> 1.2.4-alpha.0)"
    echo "  prerelease       Increment prerelease version (1.2.3-alpha.0 -> 1.2.3-alpha.1)"
    echo "  from-git         Use version from git tag"
    echo "  --dry-run        Run the script without making actual changes"
    echo ""
    echo "Examples:"
    echo "  $0 patch                    # Increment patch version (0.3.0 -> 0.3.1)"
    echo "  $0 minor                    # Increment minor version (0.3.0 -> 0.4.0)"
    echo "  $0 major                    # Increment major version (0.3.0 -> 1.0.0)"
    echo "  $0 1.2.3                   # Set specific version"
    echo "  $0 premajor                # Increment major with prerelease (0.3.0 -> 1.0.0-alpha.0)"
    echo "  $0 prerelease              # Increment prerelease (1.2.3-alpha.0 -> 1.2.3-alpha.1)"
    echo "  $0 patch --dry-run         # Test the release process without committing"
}

# Function to check if we're on the trunk branch
check_branch() {
    local current_branch=$(git branch --show-current)
    if [ "$current_branch" != "trunk" ]; then
        print_error "You must be on the 'trunk' branch to create a release."
        print_error "Current branch: $current_branch"
        print_error "Please switch to trunk: git checkout trunk"
        exit 1
    fi
}

# Function to check if working directory is clean
check_working_directory() {
    if [ -n "$(git status --porcelain)" ]; then
        print_error "Working directory is not clean. Please commit or stash your changes."
        git status --short
        exit 1
    fi
}

# Function to check if required tools are available
check_dependencies() {
    local missing_deps=()

    if ! command -v gh &> /dev/null; then
        missing_deps+=("gh (GitHub CLI)")
    fi

    if ! command -v npm &> /dev/null; then
        missing_deps+=("npm")
    fi

    if ! command -v make &> /dev/null; then
        missing_deps+=("make")
    fi

    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing required dependencies:"
        for dep in "${missing_deps[@]}"; do
            echo "  - $dep"
        done
        exit 1
    fi
}

# Function to get current version
get_current_version() {
    node -p "require('./package.json').version"
}

# Function to calculate new version without actually incrementing
calculate_new_version() {
    local current_version=$1
    local version_type=$2

    # Handle custom version numbers
    case $version_type in
        major|minor|patch|premajor|preminor|prepatch|prerelease)
            # For prerelease types, use 'alpha' as the preid
            if [[ "$version_type" =~ ^pre ]]; then
                node -p "require('semver').inc('$current_version', '$version_type', 'alpha')"
            else
                node -p "require('semver').inc('$current_version', '$version_type')"
            fi
            ;;
        from-git)
            # For from-git, we would use the git tag version
            # This is a placeholder - actual implementation would need to fetch from git
            echo "$current_version"
            ;;
        *)
            # Custom version number
            echo "$version_type"
            ;;
    esac
}

# Function to check if a version is a prerelease
is_prerelease() {
    local version=$1

    # Use semver to check if the version has prerelease identifiers
    local result=$(node -p "require('semver').prerelease('$version') !== null")

    if [ "$result" = "true" ]; then
        return 0  # It is a prerelease
    else
        return 1  # It is not a prerelease
    fi
}

# Function to validate version type
validate_version_type() {
    local version_type=$1

    # Check if it's a valid npm version type or a custom version number
    case $version_type in
        major|minor|patch|premajor|preminor|prepatch|prerelease|from-git)
            return 0
            ;;
        *)
            # Check if it's a valid semver version number
            if [[ $version_type =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$ ]]; then
                return 0
            else
                return 1
            fi
            ;;
    esac
}

# Function to get version description
get_version_description() {
    local version_type=$1
    local current_version=$(get_current_version)

    case $version_type in
        major)
            echo "major version increment"
            ;;
        minor)
            echo "minor version increment"
            ;;
        patch)
            echo "patch version increment"
            ;;
        premajor)
            echo "major version increment with prerelease"
            ;;
        preminor)
            echo "minor version increment with prerelease"
            ;;
        prepatch)
            echo "patch version increment with prerelease"
            ;;
        prerelease)
            echo "prerelease version increment"
            ;;
        from-git)
            echo "version from git tag"
            ;;
        *)
            echo "custom version: $version_type"
            ;;
    esac
}

# Function to increment version
increment_version() {
    local version_type=$1
    local current_version=$(get_current_version)
    local version_description=$(get_version_description "$version_type")
    local new_version

    print_status "Current version: $current_version"
    print_status "Incrementing version ($version_description)..."

    if [ "$DRY_RUN" = "true" ]; then
        # Calculate what the new version would be
        new_version=$(calculate_new_version "$current_version" "$version_type")
        print_success "Version would be incremented to: $new_version"
        # Store in global variable for dry run
        DRY_RUN_VERSION="$new_version"
        return
    fi

    # For prerelease types, always use 'alpha' as the preid
    case $version_type in
        premajor|preminor|prepatch|prerelease)
            npm --no-git-tag-version version "$version_type" --preid=alpha
            ;;
        *)
            npm --no-git-tag-version version "$version_type"
            ;;
    esac

    new_version=$(get_current_version)
    print_success "Version incremented to: $new_version"
}

# Function to build the project
build_project() {
    print_status "Building GutenbergKit..."

    if [ "$DRY_RUN" = "true" ]; then
        return
    fi

    make build REFRESH_DEPS=1 REFRESH_L10N=1 REFRESH_JS_BUILD=1 STRICT_L10N=1
    print_success "Build completed successfully"
}

# Function to commit changes
commit_changes() {
    local version=$1

    print_status "Adding changes to git..."

    if [ "$DRY_RUN" = "true" ]; then
        return
    fi

    git add .
    git commit -m "chore(release): $version"
    print_success "Changes committed with message: chore(release): $version"
}

# Function to create git tag
create_tag() {
    local version=$1

    print_status "Creating git tag: v$version"

    if [ "$DRY_RUN" = "true" ]; then
        return
    fi

    git tag "v$version"
    print_success "Tag created: v$version"
}

# Function to push changes
push_changes() {
    local version=$1

    print_status "Pushing changes to origin/trunk..."

    if [ "$DRY_RUN" = "true" ]; then
        return
    fi

    git push origin trunk --tags
    print_success "Changes pushed successfully"
}

# Function to create GitHub release
create_github_release() {
    local version=$1

    print_status "Creating GitHub release: v$version"

    if [ "$DRY_RUN" = "true" ]; then
        return
    fi

    gh release create "v$version" --generate-notes --title "$version"
    print_success "GitHub release created: v$version"
}

# Main function
main() {
    local version_type=""
    local DRY_RUN=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                if [ -z "$version_type" ]; then
                    version_type="$1"
                else
                    print_error "Unknown option: $1"
                    show_usage
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # Validate required argument
    if [ -z "$version_type" ]; then
        print_error "Version type is required"
        show_usage
        exit 1
    fi

    # Validate version type
    if ! validate_version_type "$version_type"; then
        print_error "Invalid version type: $version_type"
        show_usage
        exit 1
    fi

    if [ "$DRY_RUN" = "true" ]; then
        print_warning "DRY RUN MODE - No actual changes will be made"
        echo
    fi

    # Pre-flight checks
    print_status "Running pre-flight checks..."
    check_dependencies
    check_branch
    check_working_directory
    print_success "Pre-flight checks passed"
    echo

    # Get current version before incrementing
    local current_version=$(get_current_version)
    local new_version

    # Execute release steps
    increment_version "$version_type"
    echo

    # Get the new version
    if [ "$DRY_RUN" = "true" ]; then
        new_version="$DRY_RUN_VERSION"
    else
        new_version=$(get_current_version)
    fi

    build_project
    echo

    commit_changes "$new_version"
    echo

    create_tag "$new_version"
    echo

    push_changes "$new_version"
    echo

    # Only create GitHub release for non-prerelease versions
    if is_prerelease "$new_version"; then
        print_status "Skipping GitHub release creation for prerelease version"
    else
        create_github_release "$new_version"
    fi
    echo

    # Summary
    print_success "Release process completed successfully!"
    print_status "Version: $current_version -> $new_version"

    if [ "$DRY_RUN" = "true" ]; then
        print_warning "This was a dry run. No actual changes were made."
        print_status "To perform the actual release, run: make release VERSION_TYPE=$version_type"
    else
        if is_prerelease "$new_version"; then
            print_status "Prerelease tag v$new_version has been created and pushed."
            print_status "No GitHub release was created for this prerelease version."
        else
            print_status "The release is ready for integration into the WordPress app."
        fi
    fi
}

# Run main function with all arguments
main "$@"
