/**
 * WordPress dependencies
 */
import apiFetch from '@wordpress/api-fetch';

/**
 * Internal dependencies
 */
import { awaitGBKitGlobal } from './utils/bridge';
import { configureLocale } from './utils/localization';
import { initializeApiFetch } from './utils/api-fetch';
import { fetchEditorAssets } from './utils/remote-editor';
import { error } from './utils/logger';
import './index.scss';

window.wp = window.wp || {};
window.wp.apiFetch = apiFetch;

try {
	await awaitGBKitGlobal();
	initializeApiFetch();
	await configureLocale();
	const wpDependencies = await fetchEditorAssets();

	// Postpone importing `@wordpress` packages until after setting the locale
	const { initializeEditor } = await import( './utils/editor' );
	initializeEditor( wpDependencies );
} catch ( err ) {
	error( err );
	// Fallback to the local editor and display a notice. Because the remote
	// editor loading failed, it is more practical to rely upon the local
	// editor's scripts and styles for displaying the notice.
	window.location.href = 'index.html?error=gbkit_global_unavailable';
}
