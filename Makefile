
npm-dependencies:
	npm --prefix ReactApp/ install

build: npm-dependencies
	npm --prefix ReactApp/ run build

	# Copy build products into place
	cp -r ./ReactApp/dist/* ./Platforms/Apple/Library/Sources/Resources
	cp -r ./ReactApp/dist/* ./Platforms/Android/Framework/src/main/assets

dev-server: npm-dependencies
	npm --prefix ReactApp/ run dev

fmt-js: npm-dependencies
	npm --prefix ReactApp/ run format

lint-js: npm-dependencies
	npm --prefix ReactApp/ run lint
