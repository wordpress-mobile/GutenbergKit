import apiFetch from '@wordpress/api-fetch';

import Editor from './components/Editor';

window.gb = window.gb || {};

apiFetch.use(apiFetch.createRootURLMiddleware(window.gb.GUTENBERG_SITE_URL));

const username = window.gb.GUTENBERG_APPLICATION_USER;
const appPassword = window.gb.GUTENBERG_APPLICATION_PASSWORD;
const basicAuth = btoa(`${username}:${appPassword}`);

apiFetch.use((options, next) => {
	options.headers = options.headers || new Headers();
	options.headers.set('Authorization', `Basic ${basicAuth}`);

	options.headers.set('Content-Type', 'application/json');
	return next({
		...options,
		headers: {
			Authorization: `Basic ${basicAuth}`,
		},
	});
});

function App() {
	return <Editor />;
}

export default App;
