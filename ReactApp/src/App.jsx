import Editor from './components/Editor';
import { EntityProvider } from '@wordpress/core-data';

const POST_MOCK = {
	type: 'post',
};

function App({ post = POST_MOCK }) {
	return (
		<EntityProvider kind="postType" type={post.type} id={post.id}>
			<Editor post={post} />
		</EntityProvider>
	);
}

export default App;
