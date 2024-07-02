(cd ./ReactApp && npm run build)
rm -rf ./Sources/GutenbergKit/Gutenberg/
cp -r ./ReactApp/dist/. ./Sources/GutenbergKit/Gutenberg/
