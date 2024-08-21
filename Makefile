
npm-dependencies:
	npm --prefix ReactApp/ install

build: npm-dependencies
	npm --prefix ReactApp/ run build

	# Copy build products into place
	rm -rf ./Sources/GutenbergKit/Gutenberg/ ./Demo-Android/app/src/main/assets/
	cp -r ./ReactApp/dist/. ./Sources/GutenbergKit/Gutenberg/
	cp -r ./ReactApp/dist/. ./Demo-Android/app/src/main/assets/

dev-server: npm-dependencies
	npm --prefix ReactApp/ run dev

fmt-js: npm-dependencies
	npm --prefix ReactApp/ run format
