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
    echo "Usage: $0 [patch|minor|major] [--dry-run]"
    echo ""
    echo "Arguments:"
    echo "  patch|minor|major  Version increment type (required)"
    echo "  --dry-run         Run the script without making actual changes"
    echo ""
    echo "Examples:"
    echo "  $0 patch          # Increment patch version (0.3.0 -> 0.3.1)"
    echo "  $0 minor          # Increment minor version (0.3.0 -> 0.4.0)"
    echo "  $0 major          # Increment major version (0.3.0 -> 1.0.0)"
    echo "  $0 patch --dry-run # Test the release process without committing"
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
    npm run version --silent 2>/dev/null | head -n1 || node -p "require('./package.json').version"
}

# Function to increment version
increment_version() {
    local version_type=$1
    local current_version=$(get_current_version)

    print_status "Current version: $current_version"
    print_status "Incrementing version ($version_type)..."

    if [ "$DRY_RUN" = "true" ]; then
        print_warning "DRY RUN: Would increment version to $version_type"
        return
    fi

    npm --no-git-tag-version version "$version_type"
    local new_version=$(get_current_version)
    print_success "Version incremented to: $new_version"
}

# Function to build the project
build_project() {
    print_status "Building GutenbergKit..."

    if [ "$DRY_RUN" = "true" ]; then
        print_warning "DRY RUN: Would run 'make build'"
        return
    fi

    make build
    print_success "Build completed successfully"
}

# Function to commit changes
commit_changes() {
    local version=$1

    print_status "Adding changes to git..."

    if [ "$DRY_RUN" = "true" ]; then
        print_warning "DRY RUN: Would add and commit changes with message '$version'"
        return
    fi

    git add .
    git commit -m "$version"
    print_success "Changes committed with message: $version"
}

# Function to create git tag
create_tag() {
    local version=$1

    print_status "Creating git tag: v$version"

    if [ "$DRY_RUN" = "true" ]; then
        print_warning "DRY RUN: Would create tag 'v$version'"
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
        print_warning "DRY RUN: Would push to origin/trunk with tags"
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
        print_warning "DRY RUN: Would create GitHub release 'v$version'"
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
            patch|minor|major)
                version_type="$1"
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Validate required argument
    if [ -z "$version_type" ]; then
        print_error "Version type is required (patch|minor|major)"
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

    # Execute release steps
    increment_version "$version_type"
    echo

    build_project
    echo

    # Get new version after incrementing
    local new_version=$(get_current_version)

    commit_changes "$new_version"
    echo

    create_tag "$new_version"
    echo

    push_changes "$new_version"
    echo

    create_github_release "$new_version"
    echo

    # Summary
    print_success "Release process completed successfully!"
    print_status "Version: $current_version -> $new_version"

    if [ "$DRY_RUN" = "true" ]; then
        print_warning "This was a dry run. No actual changes were made."
        print_status "To perform the actual release, run: $0 $version_type"
    else
        print_status "The release is ready for integration into the WordPress app."
    fi
}

# Run main function with all arguments
main "$@"
