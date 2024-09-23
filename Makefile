
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
	echo "--- :npm: Installing NPM Dependencies"
	npm --prefix ReactApp/ ci

build: npm-dependencies
	echo "--- :node: Building Gutenberg"

	npm --prefix ReactApp/ run build

	# Copy build products into place
	echo "--- :open_file_folder: Copying Build Products into place"
	rm -rf ./Sources/GutenbergKit/Gutenberg/ ./Demo-Android/Gutenberg/src/main/assets/
	cp -r ./ReactApp/dist/. ./Sources/GutenbergKit/Gutenberg/
	cp -r ./ReactApp/dist/. ./Demo-Android/Gutenberg/src/main/assets

dev-server: npm-dependencies
	npm --prefix ReactApp/ run dev

dev-server-remote: npm-dependencies
	npm --prefix ReactApp/ run dev:remote

fmt-js: npm-dependencies
	npm --prefix ReactApp/ run format

lint-js: npm-dependencies
	npm --prefix ReactApp/ run lint

local-android-library: build
	echo "--- :android: Building Library"
	./Demo-Android/gradlew -p Demo-Android :gutenberg:publishToMavenLocal -exclude-task prepareToPublishToS3

build_swift_package: build
	$(call XCODEBUILD_CMD, build)

test_swift_package: build
	$(call XCODEBUILD_CMD, test)
