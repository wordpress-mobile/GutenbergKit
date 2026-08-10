.DEFAULT_GOAL := help

SIMULATOR_DESTINATION := OS=latest,name=iPhone 17

.PHONY: help
help: ## Display this help menu
	@echo "Usage: make [target]"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) | \
	awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2}' | \
	sort
	@echo ""

define XCODEBUILD_CMD
	@set -o pipefail && \
		xcodebuild $(1) \
		-scheme $(2) \
		-sdk iphonesimulator \
		-destination '${SIMULATOR_DESTINATION}' \
		CODE_SIGNING_ALLOWED=NO \
		| xcbeautify
endef

################################################################################
# Utility Targets
################################################################################

.PHONY: npm-dependencies
npm-dependencies: ## Install npm dependencies
# Skip unless...
# - node_modules doesn't exist
# - REFRESH_DEPS is set to true or 1
# - npm-dependencies was invoked directly (not from a recursive `$(MAKE)`)
#
# `build`'s rebuild branch invokes this as `$(MAKE) _RECURSIVE_INVOKE=1
# npm-dependencies`, which sets MAKECMDGOALS=npm-dependencies in the
# child make. Without the sentinel, that recursive call would treat
# itself as a "direct invocation" and re-run `npm ci` every time `build`
# rebuilds — even when node_modules is already populated.
	@if [ ! -d "node_modules" ] || [ "$(REFRESH_DEPS)" = "true" ] || [ "$(REFRESH_DEPS)" = "1" ] || { [ -z "$(_RECURSIVE_INVOKE)" ] && echo "$(MAKECMDGOALS)" | grep -q "^npm-dependencies$$"; }; then \
		echo "--- :npm: Installing NPM Dependencies"; \
		npm ci; \
	else \
		echo "--- :white_check_mark: Skipping NPM dependencies installation (node_modules already exists). Use REFRESH_DEPS=1 to force refresh."; \
	fi

.PHONY: prep-translations
prep-translations: ## Fetch and cache locale string files
# Skip when `dist/` already exists — translations are baked into the
# bundle at JS build time, so there is nothing for a downstream
# consumer to refresh until the bundle itself is rebuilt. This matters
# on CI agents that download `dist.tar.gz` from an upstream job:
# without it, every downstream `make` target that depends on `build`
# would re-fetch all ~50 locales from translate.wordpress.org only to
# discard the result when `build`'s recipe short-circuits.
#
# Use `REFRESH_L10N=1` (which still forces the fetch) for the explicit
# "I want fresh translations on disk" workflow — `rm -rf
# src/translations && make build` alone will not refetch, since `dist/`
# being present is read as "translations already shipped".
#
# Otherwise, skip unless...
# - src/translations doesn't contain any fetched bundles (only `.gitkeep` is committed)
# - REFRESH_L10N is set to true or 1
# - prep-translations was invoked directly
	@if [ -d "dist" ] && [ "$(REFRESH_L10N)" != "true" ] && [ "$(REFRESH_L10N)" != "1" ] && ! echo "$(MAKECMDGOALS)" | grep -q "^prep-translations$$"; then \
		echo "--- :white_check_mark: Skipping translations fetch (dist/ already built, translations baked in). Use REFRESH_L10N=1 to force refresh."; \
	elif [ -z "$$(find src/translations -maxdepth 1 -name '*.json' -print -quit 2>/dev/null)" ] || [ "$(REFRESH_L10N)" = "true" ] || [ "$(REFRESH_L10N)" = "1" ] || echo "$(MAKECMDGOALS)" | grep -q "^prep-translations$$"; then \
		echo "--- :npm: Preparing Translations"; \
		if ! npm run prep-translations -- --force; then \
			if [ "$(STRICT_L10N)" = "true" ] || [ "$(STRICT_L10N)" = "1" ]; then \
				echo "--- :x: ERROR: Translation fetching failed and STRICT_L10N is enabled"; \
				exit 1; \
			else \
				echo "--- :warning: WARNING: Translation fetching failed, but continuing anyway. Use STRICT_L10N=1 to make this fatal."; \
			fi; \
		fi; \
	else \
		echo "--- :white_check_mark: Skipping translations fetch (bundles already present in src/translations). Use REFRESH_L10N=1 to force refresh."; \
	fi

.PHONY: e2e-dependencies
e2e-dependencies: npm-dependencies ## Install E2E test dependencies
	@CHROMIUM_PATH=$$(npx playwright install --dry-run chromium 2>&1 | grep "Install location" | head -1 | sed 's/.*: *//'); \
	if [ -d "$$CHROMIUM_PATH" ]; then \
		echo "--- :white_check_mark: Playwright Chromium is already installed."; \
	elif [ -n "$$CI" ]; then \
		echo "--- :chromium: Installing Playwright Chromium"; \
		npx playwright install chromium; \
	else \
		echo ""; \
		echo "Playwright Chromium browser is not installed."; \
		echo "It is required to run E2E tests."; \
		echo ""; \
		printf "Install it now? [Y/n] "; \
		read -r answer; \
		if [ "$$answer" != "n" ] && [ "$$answer" != "N" ]; then \
			npx playwright install chromium; \
		else \
			echo "Skipping install. Run 'npx playwright install chromium' manually to install."; \
			exit 1; \
		fi; \
	fi

.PHONY: clean
clean: ## Remove build artifacts and translation string files
	npm run clean

################################################################################
# Build Targets
################################################################################

.PHONY: build
build: prep-translations ## Build the project for all platforms (iOS, Android, web)
# Skip unless...
# - dist doesn't exist
# - REFRESH_JS_BUILD is set to true or 1
# - build was invoked directly
#
# `npm-dependencies` is invoked from inside the rebuild branch rather
# than declared as a Make prereq so that downstream targets which
# depend on `build` (`test-android`, `test-swift-library`, etc.) don't
# trigger an `npm ci` they don't actually need when `dist/` is already
# populated — e.g. on CI agents that just extracted an upstream
# `dist.tar.gz` and only intend to run gradle/xcodebuild/swift.
#
# Targets that legitimately use node_modules (`test-e2e` via
# `e2e-dependencies`, `lint-js`, `test-js`, etc.) declare
# `npm-dependencies` as their own prereq.
	@if [ ! -d "dist" ] || [ "$(REFRESH_JS_BUILD)" = "true" ] || [ "$(REFRESH_JS_BUILD)" = "1" ] || echo "$(MAKECMDGOALS)" | grep -q "^build$$"; then \
		$(MAKE) _RECURSIVE_INVOKE=1 npm-dependencies && \
		echo "--- :node: Building Gutenberg" && \
		npm run build && \
		$(MAKE) inject-sourcemap-debug-ids && \
		echo "--- :open_file_folder: Copying Build Products into place" && \
		$(MAKE) copy-dist-ios && \
		$(MAKE) copy-dist-android; \
	else \
		echo "--- :white_check_mark: Skipping JS build (dist already exists). Use REFRESH_JS_BUILD=1 to force refresh."; \
	fi

# Inject Sentry Debug IDs into the built JS and its source maps. This runs
# BETWEEN `npm run build` and the `copy-dist-*` targets so the `//# debugId=`
# comment lands in `dist/` and is copied into the shipped bundles, while the
# matching `debug_id` is written into the `.map` files that get uploaded to
# Sentry. Debug IDs let Sentry match maps to events regardless of the (unstable,
# per-install) on-device file paths — the only reliable approach for GutenbergKit's
# WebView, where path-based matching fails.
#
# `@sentry/cli sourcemaps inject` only rewrites files with adjacent maps; it needs
# no auth token (uploading, which does, stays host-side). The injected UUIDs are
# deterministic (content-hashed), so builds remain reproducible.
.PHONY: inject-sourcemap-debug-ids
inject-sourcemap-debug-ids:
	@echo "--- :sentry: Injecting source map Debug IDs"
	@npx sentry-cli sourcemaps inject dist

# The `find ... -delete` after each copy strips source maps from the native
# bundles. Maps are emitted into `dist/` (see `vite.config.js`) so build tooling
# can deliver them to Sentry, but they must NOT ship inside the app: they'd bloat
# the binary and expose de-minified source. `dist/` itself keeps its maps for the
# upload step. Stripping here (rather than only in CI) covers every consumer of
# these targets — local `make build`, CI, and `bin/release.sh` (which commits the
# iOS bundle via `git add .`).
.PHONY: copy-dist-ios
copy-dist-ios:
	@rm -rf ./ios/Sources/GutenbergKitResources/Gutenberg/
	@mkdir -p ./ios/Sources/GutenbergKitResources/Gutenberg
	@cp -r ./dist/. ./ios/Sources/GutenbergKitResources/Gutenberg/
	@find ./ios/Sources/GutenbergKitResources/Gutenberg -name '*.map' -delete
	@touch ./ios/Sources/GutenbergKitResources/Gutenberg/.gitkeep

.PHONY: copy-dist-android
copy-dist-android:
	@rm -rf ./android/Gutenberg/src/main/assets/
	@cp -r ./dist/. ./android/Gutenberg/src/main/assets
	@find ./android/Gutenberg/src/main/assets -name '*.map' -delete

.PHONY: build-swift-package
build-swift-package: build ## Build the Swift package for iOS
	$(call XCODEBUILD_CMD, build, GutenbergKit)

.PHONY: build-resources-xcframework
build-resources-xcframework: build ## Build GutenbergKitResources XCFramework
# `build` short-circuits `copy-dist-ios` when `dist/` already exists (e.g. in
# CI, after extracting an upstream dist tarball), so call it explicitly here
# to guarantee the XCFramework ships the just-built dist rather than whatever
# was committed at HEAD.
	@$(MAKE) copy-dist-ios
	@echo "--- :swift: Building GutenbergKitResources XCFramework"
	./build_xcframework.sh

.PHONY: local-android-library
local-android-library: build ## Build the Android library to local Maven
	@echo "--- :android: Building Library"
	./android/gradlew -p ./android :gutenberg:publishToMavenLocal -exclude-task prepareToPublishToS3

################################################################################
# Development Targets
################################################################################

.PHONY: dev-server
dev-server: npm-dependencies ## Start the development server
	npm run dev

.PHONY: dev-server-force
dev-server-force: npm-dependencies ## Start the development server, ignore the cache and re-bundle
	npm run dev:force

.PHONY: dev-tools
dev-tools: npm-dependencies ## Start the React Developer Tools
	npm run dev:tools

.PHONY: preview
preview: npm-dependencies ## Preview the production build locally
	npm run preview

################################################################################
# Local WordPress Environment Targets (wp-env)
################################################################################

.PHONY: wp-env-start
wp-env-start: npm-dependencies ## Start the local WordPress environment (RESET=1 to regenerate credentials)
	npm run wp-env start -- --runtime=playground
	@RESET=$(RESET) bash bin/wp-env-setup.sh

.PHONY: wp-env-stop
wp-env-stop: ## Stop the local WordPress environment
	npm run wp-env stop

.PHONY: wp-env-clean
wp-env-clean: ## Stop wp-env and remove all data (fresh start)
	npm run wp-env destroy
	@rm -f .wp-env.credentials.json

.PHONY: wp-env-android
wp-env-android: ## Remap wp-env site URLs for the Android emulator and restart
	@cp wp-env/android-url-override.php wp-env/mu-plugins/gutenbergkit-android-urls.php
	@RESET=1 $(MAKE) wp-env-start

.PHONY: wp-env-android-reset
wp-env-android-reset: ## Remove the Android emulator URL remap and restart
	@rm -f wp-env/mu-plugins/gutenbergkit-android-urls.php
	@RESET=1 $(MAKE) wp-env-start

################################################################################
# Code Quality Targets
################################################################################

.PHONY: format
format: npm-dependencies ## Format code
	npm run format

.PHONY: lint-js
lint-js: npm-dependencies ## Lint JavaScript code
	npm run lint:js

.PHONY: lint-fix-js
lint-js-fix: npm-dependencies ## Lint and auto-fix JavaScript code
	npm run lint:js:fix

.PHONY: lint-android
lint-android: ## Lint Android code with Detekt
	@echo "--- :android: Running Detekt"
	./android/gradlew -p ./android detekt

# Runs SwiftLint via the BuildTools package plugin, which pins the SwiftLint version
# to `swiftlint_version` in .swiftlint.yml. SDKROOT is pinned to the macOS SDK so the
# plugin builds even when invoked from an environment that targets iOS.
#
# Set SWIFT_LINT_PATHS to lint specific files instead of the whole project, e.g.
# `make lint-swift SWIFT_LINT_PATHS=ios/Sources/GutenbergKit/Sources/EditorService.swift`.
# Only files are honored — passing a directory silently falls back to linting the
# whole project.
#
# Separate multiple files with newlines rather than spaces, so that paths
# containing spaces stay intact:
#
#   make lint-swift SWIFT_LINT_PATHS="$(git diff --name-only -- '*.swift')"
#
# The plugin only honors explicit paths when the last argument is an existing
# file, so the paths must always be appended last — after flags like `--fix` — or
# the plugin silently falls back to linting the whole project.
#
# The paths are exported and re-split on newlines inside the recipe rather than
# expanded inline as $(SWIFT_LINT_PATHS). Inline expansion pastes the value into
# the recipe text, where the shell word-splits a path containing spaces into
# fragments that are not existing files — silently triggering that same
# whole-project fallback. Going through the environment avoids that entirely.
SWIFT_LINT_PATHS ?=
export SWIFT_LINT_PATHS

SWIFTLINT = IFS="$$(printf '\nx')"; IFS="$${IFS%x}"; \
	set -f; set -- $${SWIFT_LINT_PATHS:+$$SWIFT_LINT_PATHS}; \
	unset IFS; set +f; \
	SDKROOT="$$(xcrun --sdk macosx --show-sdk-path)" \
	swift package --package-path BuildTools plugin \
	--allow-writing-to-directory "$(CURDIR)" --allow-writing-to-package-directory \
	swiftlint --working-directory "$(CURDIR)" --quiet

.PHONY: lint-swift
lint-swift: ## Lint Swift code
	@echo "--- :swift: Running SwiftLint"
	@$(SWIFTLINT) "$$@"

.PHONY: lint-swift-fix
lint-swift-fix: ## Lint and auto-fix Swift code
	@echo "--- :swift: Running SwiftLint (autocorrect)"
	@$(SWIFTLINT) --fix "$$@"

################################################################################
# Testing Targets
################################################################################

.PHONY: test-e2e
test-e2e: e2e-dependencies ## Run end-to-end tests
	@if [ ! -d "dist" ]; then \
		$(MAKE) build; \
	else \
		echo "--- :white_check_mark: Using existing build. Use 'make build REFRESH_JS_BUILD=1' to rebuild."; \
	fi
	npm run test:e2e

.PHONY: test-e2e-ui
test-e2e-ui: e2e-dependencies ## Run end-to-end tests in UI mode
	@if [ ! -d "dist" ]; then \
		$(MAKE) build; \
	else \
		echo "--- :white_check_mark: Using existing build. Use 'make build REFRESH_JS_BUILD=1' to rebuild."; \
	fi
	npm run test:e2e:ui

.PHONY: test-js
test-js: npm-dependencies ## Run JavaScript tests
	npm run test:unit

.PHONY: test-js-watch
test-js-watch: npm-dependencies ## Run JavaScript tests in watch mode
	npm run test:unit:watch

.PHONY: test-swift-package
test-swift-package: build ## Run Swift package tests in the iOS Simulator
	$(call XCODEBUILD_CMD, test, GutenbergKit-Package)

.PHONY: test-swift-library
test-swift-library: build ## Run Swift package tests against the host platform via `swift test`
	swift test

.PHONY: test-ios-e2e
test-ios-e2e: ## Run iOS E2E tests against the production build
	@if [ ! -d "dist" ]; then \
		$(MAKE) build; \
	else \
		echo "--- :white_check_mark: Using existing build. Use 'make build REFRESH_JS_BUILD=1' to rebuild."; \
	fi
	@echo "--- :open_file_folder: Copying build into iOS bundle"
	@$(MAKE) copy-dist-ios
	@echo "--- :ios: Running iOS E2E Tests (production build)"
	@set -o pipefail && \
		xcodebuild test \
		-project ./ios/Demo-iOS/Gutenberg.xcodeproj \
		-scheme GutenbergUITests \
		-sdk iphonesimulator \
		-destination '${SIMULATOR_DESTINATION}' \
		| xcbeautify

.PHONY: test-ios-e2e-dev
test-ios-e2e-dev: ## Run iOS E2E tests against the Vite dev server (must be running)
	@if ! curl -sf http://localhost:5173 > /dev/null 2>&1; then \
		echo "Error: Dev server is not running at http://localhost:5173"; \
		echo "Start it first with: make dev-server"; \
		exit 1; \
	fi
	@echo "--- :ios: Running iOS E2E Tests (dev server)"
	@set -o pipefail && \
		TEST_RUNNER_GUTENBERG_EDITOR_URL=http://localhost:5173 \
		xcodebuild test \
		-project ./ios/Demo-iOS/Gutenberg.xcodeproj \
		-scheme GutenbergUITests \
		-sdk iphonesimulator \
		-destination '${SIMULATOR_DESTINATION}' \
		| xcbeautify

.PHONY: test-android
test-android: build ## Run Android tests
# `build` short-circuits `copy-dist-android` when `dist/` already exists
# (e.g. in CI, after extracting an upstream `dist.tar.gz`), so copy
# explicitly here to guarantee the tests run against the current dist
# rather than whatever was committed at HEAD.
	@echo "--- :open_file_folder: Copying build into Android bundle"
	@rm -rf ./android/Gutenberg/src/main/assets/
	@cp -r ./dist/. ./android/Gutenberg/src/main/assets
	@echo "--- :android: Running Android Tests"
	./android/gradlew -p ./android :gutenberg:test

# Ensure an Android device or emulator is available for instrumented tests.
# Checks for any connected device; if none found, boots the first available AVD.
define ENSURE_ANDROID_DEVICE
	@if adb devices 2>/dev/null | tail -n +2 | grep -q 'device$$'; then \
		echo "--- :white_check_mark: Android device already connected."; \
	else \
		AVD=$$("$$ANDROID_HOME/emulator/emulator" -list-avds 2>/dev/null | head -n 1); \
		if [ -z "$$AVD" ]; then \
			echo "Error: No Android device connected and no AVDs found."; \
			echo "Connect a device, start an emulator, or create an AVD with Android Studio."; \
			exit 1; \
		fi; \
		echo "--- :rocket: Booting Android emulator ($$AVD)..."; \
		"$$ANDROID_HOME/emulator/emulator" -avd "$$AVD" -no-snapshot-load -no-audio -no-window &>/dev/null & \
		EMULATOR_PID=$$!; \
		echo "--- :hourglass: Waiting for emulator to boot..."; \
		adb wait-for-device; \
		BOOT_WAIT=0; \
		while [ "$$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" != "1" ]; do \
			BOOT_WAIT=$$((BOOT_WAIT + 1)); \
			if [ $$BOOT_WAIT -gt 60 ]; then \
				echo "Error: Emulator boot timed out after 120 seconds."; \
				kill $$EMULATOR_PID 2>/dev/null; \
				exit 1; \
			fi; \
			sleep 2; \
		done; \
		echo "--- :white_check_mark: Emulator booted."; \
	fi
endef

.PHONY: test-android-e2e
test-android-e2e: ## Run Android E2E tests against the production build
	@if [ ! -d "dist" ]; then \
		$(MAKE) build; \
	else \
		echo "--- :white_check_mark: Using existing build. Use 'make build REFRESH_JS_BUILD=1' to rebuild."; \
	fi
	@echo "--- :open_file_folder: Copying build into Android bundle"
	@rm -rf ./android/Gutenberg/src/main/assets/
	@cp -r ./dist/. ./android/Gutenberg/src/main/assets
	$(ENSURE_ANDROID_DEVICE)
	@echo "--- :android: Running Android E2E Tests (production build)"
	./android/gradlew -p ./android :app:connectedDebugAndroidTest

.PHONY: test-android-e2e-dev
test-android-e2e-dev: ## Run Android E2E tests against the Vite dev server (must be running)
	@if ! curl -sf http://localhost:5173 > /dev/null 2>&1; then \
		echo "Error: Dev server is not running at http://localhost:5173"; \
		echo "Start it first with: make dev-server"; \
		exit 1; \
	fi
	$(ENSURE_ANDROID_DEVICE)
	@echo "--- :android: Running Android E2E Tests (dev server)"
	./android/gradlew -p ./android :app:connectedDebugAndroidTest

.PHONY: test-android-library-e2e
test-android-library-e2e: build ## Run instrumented tests for the Gutenberg Android library module
# `build` short-circuits `copy-dist-android` when `dist/` already exists
# (e.g. in CI, after extracting an upstream `dist.tar.gz`), so copy
# explicitly here to guarantee the instrumented tests run against the
# current dist rather than whatever was committed at HEAD.
	@echo "--- :open_file_folder: Copying build into Android bundle"
	@rm -rf ./android/Gutenberg/src/main/assets/
	@cp -r ./dist/. ./android/Gutenberg/src/main/assets
	$(ENSURE_ANDROID_DEVICE)
	@echo "--- :android: Running Android Library Instrumented Tests"
	@mkdir -p android/Gutenberg/build/outputs/buildkite-logs
	@adb logcat -c
	@./android/gradlew -p ./android :Gutenberg:connectedDebugAndroidTest; \
	EXIT=$$?; \
	adb logcat -d > android/Gutenberg/build/outputs/buildkite-logs/device-logcat.txt; \
	echo "--- :mag: Buildkite Test Engine collector output"; \
	if grep -E 'Buildkite|BUILDKITE_ANALYTICS' android/Gutenberg/build/outputs/buildkite-logs/device-logcat.txt; then :; \
	else \
		echo "(no Buildkite collector output found in device logcat — listener may not have registered)"; \
	fi; \
	if grep -q 'BuildkiteLogger-ERROR\|Buildkite-InstrumentedTestCollector-ERROR' android/Gutenberg/build/outputs/buildkite-logs/device-logcat.txt; then \
		echo "+++ :rotating_light: Buildkite Test Engine upload failed (see excerpt above)"; \
		EXIT=1; \
	fi; \
	exit $$EXIT

################################################################################
# Release Target
################################################################################

.PHONY: release
release: ## Create and publish a new release
	@echo "--- :rocket: Starting GutenbergKit Release Process"
	@echo "Usage: make release VERSION_TYPE=[<newversion> | major | minor | patch | premajor | preminor | prepatch | prerelease | from-git] [DRY_RUN=true]"
	@echo ""
	@echo "Version Types:"
	@echo "  <newversion>     Custom version number (e.g., 1.2.3)"
	@echo "  major            Increment major version (1.0.0 -> 2.0.0)"
	@echo "  minor            Increment minor version (1.2.0 -> 1.3.0)"
	@echo "  patch            Increment patch version (1.2.3 -> 1.2.4)"
	@echo "  premajor         Increment major version and add prerelease (1.2.3 -> 2.0.0-alpha.0)"
	@echo "  preminor         Increment minor version and add prerelease (1.2.3 -> 1.3.0-alpha.0)"
	@echo "  prepatch         Increment patch version and add prerelease (1.2.3 -> 1.2.4-alpha.0)"
	@echo "  prerelease       Increment prerelease version (1.2.3-alpha.0 -> 1.2.3-alpha.1)"
	@echo "  from-git         Use version from git tag"
	@echo ""
	@echo "Examples:"
	@echo "  make release VERSION_TYPE=patch"
	@echo "  make release VERSION_TYPE=minor"
	@echo "  make release VERSION_TYPE=major"
	@echo "  make release VERSION_TYPE=1.2.3"
	@echo "  make release VERSION_TYPE=premajor"
	@echo "  make release VERSION_TYPE=prerelease"
	@echo "  make release VERSION_TYPE=patch DRY_RUN=true"
	@echo ""
	@if [ -z "$(VERSION_TYPE)" ]; then \
		echo "Error: VERSION_TYPE is required."; \
		echo "Use one of: <newversion>, major, minor, patch, premajor, preminor, prepatch, prerelease, from-git"; \
		exit 1; \
	fi
	@if [ "$(DRY_RUN)" = "true" ]; then \
		./bin/release.sh $(VERSION_TYPE) --dry-run; \
	else \
		./bin/release.sh $(VERSION_TYPE); \
	fi
