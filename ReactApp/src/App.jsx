/**
 * Internal dependencies
 */
import Editor from './components/Editor';
import EditorLoadNotice from './components/EditorLoadNotice';

function App(props) {
	return (
		<>
			<EditorLoadNotice />
			<Editor {...props} />
		</>
	);
}

export default App;
