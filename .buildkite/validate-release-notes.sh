#!/usr/bin/env bash

set -euo pipefail

# Throwaway validation for wordpress-mobile/GutenbergKit#913. Do not merge.

repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"
expected_entries=58

generate_notes() {
  # fastlane runs actions from `..`, so this must start in `fastlane/`.
  (cd "$repo_root/fastlane" && bundle exec ruby -e '
    require "fastlane"
    Fastlane.load_actions
    fastfile = Fastlane::FastFile.new(File.join(ARGV[0], "fastlane/Fastfile"))
    puts "TOOLKIT VERSION: #{Gem.loaded_specs["fastlane-plugin-wpmreleasetoolkit"].version}"
    puts fastfile.generated_release_notes(version: "v0.20.0", token: ENV.fetch("GITHUB_TOKEN"))
  ' "$repo_root")
}

echo '--- :rubygems: Setting up Gems'
install_gems

echo '--- :white_check_mark: Positive: notes for v0.20.0 on the locked release-toolkit'
generate_notes > positive.log 2>&1 || { cat positive.log; echo "FAIL: generating notes on the locked toolkit errored"; exit 1; }
grep -v '^\[' positive.log
grep -q '^TOOLKIT VERSION: 15.4.1$' positive.log || { echo "FAIL: expected release-toolkit 15.4.1"; exit 1; }
grep -q '^## New PRs since \[v0.19.0\](https://github.com/wordpress-mobile/GutenbergKit/releases/tag/v0.19.0)$' positive.log \
  || { echo "FAIL: missing the toolkit heading against v0.19.0"; exit 1; }
entries=$(grep -c '^\* ' positive.log || true)
[[ "$entries" == "$expected_entries" ]] || { echo "FAIL: expected $expected_entries entries, got $entries"; exit 1; }
echo "PASS: 15.4.1 generated $entries entries against v0.19.0"

echo '--- :x: Negative: the same call on release-toolkit 15.3.0 must hit the original 422'
broken=$(mktemp -d)
cp Gemfile Gemfile.lock "$broken/"
sed -i '' "s/^gem 'fastlane-plugin-wpmreleasetoolkit'.*/gem 'fastlane-plugin-wpmreleasetoolkit', '= 15.3.0'/" "$broken/Gemfile"
export BUNDLE_PATH="$repo_root/vendor/bundle"
BUNDLE_GEMFILE="$broken/Gemfile" bundle lock --update fastlane-plugin-wpmreleasetoolkit --conservative
BUNDLE_GEMFILE="$broken/Gemfile" bundle install --quiet
if BUNDLE_GEMFILE="$broken/Gemfile" generate_notes > negative.log 2>&1; then
  grep -v '^\[' negative.log
  echo "FAIL: 15.3.0 generated notes, so this step cannot tell a fixed toolkit from a broken one"
  exit 1
fi
grep -q '^TOOLKIT VERSION: 15.3.0$' negative.log || { cat negative.log; echo "FAIL: negative run did not load 15.3.0"; exit 1; }
{ grep 'generate-notes: 422' negative.log && grep 'Invalid property /configuration_file_path: data cannot be null' negative.log; } \
  || { cat negative.log; echo "FAIL: 15.3.0 failed, but not with the configuration_file_path 422"; exit 1; }
echo "PASS: 15.3.0 fails with the original 422"
