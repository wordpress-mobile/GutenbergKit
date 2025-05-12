SIMULATOR_DESTINATION := OS=17.5,name=iPhone 15 Plus

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

dev-server-remote: npm-dependencies
	npm run dev:remote

fmt-js: npm-dependencies
	npm run format

lint-js: npm-dependencies
	npm run lint

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
