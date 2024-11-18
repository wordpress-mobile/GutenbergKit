/**
 * Internal dependencies
 */
import Editor from './components/editor';
import EditorLoadNotice from './components/editor-load-notice';

function App(props) {
	return (
		<>
			<EditorLoadNotice />
			<Editor {...props} />
		</>
	);
}

export default App;
