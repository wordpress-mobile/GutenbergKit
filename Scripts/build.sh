(cd ./GutenbergReactApp && npm run build)
rm -rf ./GutenbergKit/Sources/GutenbergKit/Gutenberg/
cp -r ./GutenbergReactApp/build/. ./GutenbergKit/Sources/GutenbergKit/Gutenberg/