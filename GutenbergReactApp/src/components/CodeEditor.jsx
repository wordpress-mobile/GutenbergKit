// import { React } from 'react';

// import { Editor } from '@monaco-editor/react';

// /* FIXME: connect with the app */
//
// Temporarily disable because it was breaking some styles. It needs to be iframes properly
//
// function CodeEditor(props) {
//     return <div className="gbkit-code-editor_container">
//         <Editor
//             defaultValue={props.value}
//             height="100vh"
//             defaultLanguage="html"
//             options={{
//                 minimap: { enabled: false },
//                 fontSize: 16,
//                 scrollbar: {
//                     horizontalScrollbarSize: 5,
//                     verticalScrollbarSize: 5,
//                 },
//                 roundedSelection: true,
//                 overviewRulerLanes: 0,
//                 hideCursorInOverviewRuler: true,
//                 cursorStyleUnfocused: "none",
//                 lineNumbersMinChars: 3,
//                 lineDecorationsWidth: 4,
//                 padding: { top: 12, bottom: 12 },
//                 wordWrap: "on"
//             }}
//         />
//     </div>;
// }

// var meta = document.createElement('meta');
// meta.setAttribute('name', 'viewport');
// meta.setAttribute('content', 'width=device-width');
// document.getElementsByTagName('head')[0].appendChild(meta);

// export default CodeEditor;