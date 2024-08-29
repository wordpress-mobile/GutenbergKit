/**
 * Internal dependencies
 */
import { getPost } from './misc/Helpers';
import Editor from './components/Editor';

const post = getPost();

function App() {
	return <Editor post={post} />;
}

export default App;
