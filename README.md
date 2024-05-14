A proof of concept for a Gutenberg editor as a React app embedded in a native iOS app.

## Development

### GutenbergReactApp

The ReactJS app embeded in the native GutenbergKit module.

To launch the app in the browser, run:

```
npm install // On first use
npm start
```

To build the app and incorporate the changes in the Swift module, run:

```
./Scripts/build.sh
```

### GutenbergKit

A Swift package with native wrappers for the Gutenberg editor.

