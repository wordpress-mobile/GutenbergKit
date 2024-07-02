A proof of concept for a Gutenberg editor as a React app embedded in a native iOS app.

## Development

### React App

The ReactJS app is embedded in the native GutenbergKit module.

To launch the app in the browser, run:

```
cd ./ReactApp
npm install // On first use
npm run dev
```

### GutenbergKit

A Swift package with native wrappers for the Gutenberg editor.

### Demo

A host app that can be used to test the changes made to the editor quickly. 

By default, the demo app uses a production build of the React app included in the `GutenbergKit` package. During development, make sure to run the React app and pass the localhost URL as an environment variable of the demo app.

<img width="725" alt="Screenshot 2024-07-01 at 10 46 19 PM" src="https://github.com/kean/GutenbergKit/assets/1567433/cdc8a28a-c621-4b8e-bc7a-31361694434c">

If you are using SwiftUI previews, make sure to point them to the localhost programatically:

```
#Preview {
    NavigationStack {
//        EditorView()
        EditorView(editorURL: URL(string: "http://localhost:5173/")!)
    }
}
```

## Production

To build the React app for production and incorporate the changes in the `GutenbergKit` Swift module, run:

```
./Scripts/build.sh
```
