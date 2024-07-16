(cd ./ReactApp && npm run build)
rm -rf ./Sources/GutenbergKit/Gutenberg/ ./app/src/main/assets
cp -r ./ReactApp/dist/. ./Sources/GutenbergKit/Gutenberg/
cp -r ./ReactApp/dist/. ./app/src/main/assets/
