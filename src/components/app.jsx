/**
 * Internal dependencies
 */
import Editor from './editor';
import EditorLoadNotice from './editor-load-notice';

function App(props) {
	return (
		<>
			<EditorLoadNotice />
			<Editor {...props} />
		</>
	);
}

export default App;
