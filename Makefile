.DEFAULT_GOAL := help

SIMULATOR_DESTINATION := platform=iOS Simulator,name=iPhone 17

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
		-scheme GutenbergKit \
		-sdk iphonesimulator \
		-destination '${SIMULATOR_DESTINATION}' \
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
# - npm-dependencies was invoked directly
	@if [ ! -d "node_modules" ] || [ "$(REFRESH_DEPS)" = "true" ] || [ "$(REFRESH_DEPS)" = "1" ] || echo "$(MAKECMDGOALS)" | grep -q "^npm-dependencies$$"; then \
		echo "--- :npm: Installing NPM Dependencies"; \
		npm ci; \
	else \
		echo "--- :white_check_mark: Skipping NPM dependencies installation (node_modules already exists). Use REFRESH_DEPS=1 to force refresh."; \
	fi

.PHONY: prep-translations
prep-translations: ## Fetch and cache locale string files
# Skip unless...
# - src/translations doesn't exist
# - REFRESH_L10N is set to true or 1
# - prep-translations was invoked directly
	@if [ ! -d "src/translations" ] || [ "$(REFRESH_L10N)" = "true" ] || [ "$(REFRESH_L10N)" = "1" ] || echo "$(MAKECMDGOALS)" | grep -q "^prep-translations$$"; then \
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
		echo "--- :white_check_mark: Skipping translations fetch (src/translations already exists). Use REFRESH_L10N=1 to force refresh."; \
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
build: npm-dependencies prep-translations ## Build the project for all platforms (iOS, Android, web)
# Skip unless...
# - dist doesn't exist
# - REFRESH_JS_BUILD is set to true or 1
# - build was invoked directly
	@if [ ! -d "dist" ] || [ "$(REFRESH_JS_BUILD)" = "true" ] || [ "$(REFRESH_JS_BUILD)" = "1" ] || echo "$(MAKECMDGOALS)" | grep -q "^build$$"; then \
		echo "--- :node: Building Gutenberg"; \
		npm run build; \
		echo "--- :open_file_folder: Copying Build Products into place"; \
		rm -rf ./ios/Sources/GutenbergKit/Gutenberg/ ./android/Gutenberg/src/main/assets/; \
		cp -r ./dist/. ./ios/Sources/GutenbergKit/Gutenberg/; \
		cp -r ./dist/. ./android/Gutenberg/src/main/assets; \
	else \
		echo "--- :white_check_mark: Skipping JS build (dist already exists). Use REFRESH_JS_BUILD=1 to force refresh."; \
	fi

.PHONY: build-swift-package
build-swift-package: build ## Build the Swift package for iOS
	$(call XCODEBUILD_CMD, build)

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

.PHONY: lint-swift
lint-swift: ## Lint Swift code
	swift package plugin swiftlint

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
test-swift-package: build ## Run Swift package tests
	$(call XCODEBUILD_CMD, test)

.PHONY: test-ios-e2e
test-ios-e2e: ## Run iOS E2E tests against the production build
	@if [ ! -d "dist" ]; then \
		$(MAKE) build; \
	else \
		echo "--- :white_check_mark: Using existing build. Use 'make build REFRESH_JS_BUILD=1' to rebuild."; \
	fi
	@if [ ! -d "./ios/Sources/GutenbergKit/Gutenberg" ]; then \
		echo "--- :open_file_folder: Copying build into iOS bundle"; \
		cp -r ./dist/. ./ios/Sources/GutenbergKit/Gutenberg/; \
	fi
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
test-android: ## Run Android tests
	@echo "--- :android: Running Android Tests"
	./android/gradlew -p ./android :gutenberg:test

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
