/**
 * Internal dependencies
 */
import Editor from './editor';
import EditorLoadNotice from './editor-load-notice';

/**
 * Entry component rendering the editor and surround UI.
 *
 * @param {Object} props Component props.
 *
 * @return {JSX.Element} The rendered App component.
 */
function App(props) {
	return (
		<>
			<EditorLoadNotice />
			<Editor {...props} />
		</>
	);
}

export default App;
