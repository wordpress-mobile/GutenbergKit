(cd ./GutenbergReactApp && npm run build)
rm -rf ./Sources/GutenbergKit/Gutenberg/
cp -r ./GutenbergReactApp/dist/. ./Sources/GutenbergKit/Gutenberg/
