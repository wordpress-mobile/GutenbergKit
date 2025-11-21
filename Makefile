SIMULATOR_DESTINATION := OS=26.0,name=iPhone 17

define XCODEBUILD_CMD
	@set -o pipefail && \
		xcodebuild $(1) \
		-scheme GutenbergKit \
		-sdk iphonesimulator \
		-destination '${SIMULATOR_DESTINATION}' \
		| xcbeautify
endef

npm-dependencies:
	@if [ "$(SKIP_DEPS)" != "true" ] && [ "$(SKIP_DEPS)" != "1" ]; then \
		echo "--- :npm: Installing NPM Dependencies"; \
		npm ci; \
	fi

prep-translations:
	@if [ "$(SKIP_L10N)" != "true" ] && [ "$(SKIP_L10N)" != "1" ]; then \
		echo "--- :npm: Preparing Translations"; \
		npm run prep-translations -- --force; \
	fi

build: npm-dependencies prep-translations
	echo "--- :node: Building Gutenberg"

	npm run build

	# Copy build products into place
	echo "--- :open_file_folder: Copying Build Products into place"
	rm -rf ./ios/Sources/GutenbergKit/Gutenberg/ ./android/Gutenberg/src/main/assets/
	cp -r ./dist/. ./ios/Sources/GutenbergKit/Gutenberg/
	cp -r ./dist/. ./android/Gutenberg/src/main/assets

dev-server: npm-dependencies
	npm run dev

dev-tools: npm-dependencies
	npm run devtools

fmt-js: npm-dependencies
	npm run format

lint-js: npm-dependencies
	npm run lint

test-js: npm-dependencies
	npm run test -- run

lint-swift:
	swift package plugin swiftlint

local-android-library: build
	echo "--- :android: Building Library"
	./android/gradlew -p ./android :gutenberg:publishToMavenLocal -exclude-task prepareToPublishToS3

test-android:
	echo "--- :android: Running Android Tests"
	./android/gradlew -p ./android :gutenberg:test

build-swift-package: build
	$(call XCODEBUILD_CMD, build)

test-swift-package: build
	$(call XCODEBUILD_CMD, test)

release:
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
