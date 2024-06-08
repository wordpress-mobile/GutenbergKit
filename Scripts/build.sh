(cd ./GutenbergReactApp && npm run build)
rm -rf ./GutenbergKit/Sources/GutenbergKit/Gutenberg/
cp -r ./GutenbergReactApp/dist/. ./GutenbergKit/Sources/GutenbergKit/Gutenberg/