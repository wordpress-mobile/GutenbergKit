import { getGBKit } from './misc/Helpers.js';
import { loadRemoteEditor } from './misc/editor.js';
import './index.css';

window.GBKit = getGBKit();
initializeEditor();

async function initializeEditor() {
	// Load remote editor scripts
	// TODO: Make a remote editor optional, fallback to a local editor
	await loadRemoteEditor(window);

	// Using the remote editor globals, render the editor
	const { createRoot } = window.ReactDOM;
	const { StrictMode } = window.wp.element;
	const { default: App } = await import('./App.jsx');
	createRoot(document.getElementById('root')).render(
		<StrictMode>
			<App />
		</StrictMode>
	);
}
