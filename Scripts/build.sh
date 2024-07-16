(cd ./ReactApp && npm run build)
rm -rf ./Sources/GutenbergKit/Gutenberg/ ./Demo-Android/app/src/main/assets/
cp -r ./ReactApp/dist/. ./Sources/GutenbergKit/Gutenberg/
cp -r ./ReactApp/dist/. ./Demo-Android/app/src/main/assets/
