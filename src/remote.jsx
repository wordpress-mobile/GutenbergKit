/**
 * WordPress dependencies
 */
import apiFetch from '@wordpress/api-fetch';

/**
 * Internal dependencies
 */
import { getGBKit, getPost, waitForGBKit } from './utils/bridge';
import { initializeApiFetch } from './utils/api-fetch-setup';
import './index.scss';
import defaultEditorStyles from '@wordpress/block-editor/build-style/default-editor-styles.css?inline';

/**
 * Locally-sourced Gutenberg packages; remote copies are discarded to avoid
 * conflicts
 */
const localGutenbergPackages = [ 'api-fetch' ];

try {
	await waitForGBKit();
	window.wp = window.wp || {};
	window.wp.apiFetch = apiFetch;
	initializeApiFetch();
	await initalizeRemoteEditor();
} catch ( error ) {
	const root = document.getElementById( 'root' );
	if ( root ) {
		const { createRoot, createElement, StrictMode } =
			window.wp.element || {};
		if ( createRoot && createElement && StrictMode ) {
			createRoot( root ).render(
				createElement(
					StrictMode,
					null,
					createElement(
						'div',
						{ className: 'error-message' },
						`Failed to initialize editor: ${ error.message }`
					)
				)
			);
		} else {
			root.innerHTML = `<div class="error-message">Failed to initialize editor: ${ error.message }</div>`;
		}
	}
}

/**
 * Configure editor settings and styles, and render the editor.
 */
async function initalizeRemoteEditor() {
	try {
		const { themeStyles, hideTitle, siteApiRoot, siteApiNamespace } =
			getGBKit();
		const { styles, scripts } = await apiFetch( {
			url: `${ siteApiRoot }wpcom/v2/${ siteApiNamespace[ 0 ] }/editor-assets`,
		} );
		await loadAssets( [ ...styles, ...scripts ].join( '' ) );

		// Utilize remote-loaded globals rather than importing local modules
		const { dispatch } = window.wp.data;
		const { store: editorStore } = window.wp.editor;
		const { store: preferencesStore } = window.wp.preferences;

		// TODO: Provide this data from the host app
		apiFetch( { path: `/wp-block-editor/v1/settings` } )
			.then( ( editorSettings ) => {
				dispatch( editorStore ).updateEditorSettings( editorSettings );
			} )
			.catch( () => {
				const editorSettings = {
					defaultEditorStyles: [ { css: defaultEditorStyles } ],
				};
				dispatch( editorStore ).updateEditorSettings( editorSettings );
			} );

		const preferenceDispatch = dispatch( preferencesStore );
		preferenceDispatch.setDefaults( 'core', {
			fixedToolbar: true,
		} );
		preferenceDispatch.setDefaults( 'core/edit-post', {
			themeStyles,
		} );

		const post = getPost();
		const { default: Layout } = await import(
			'./components/layout/index.jsx'
		);
		const { createRoot, createElement, StrictMode } = window.wp.element;
		const { registerCoreBlocks } = window.wp.blockLibrary;
		registerCoreBlocks();
		createRoot( document.getElementById( 'root' ) ).render(
			createElement(
				StrictMode,
				null,
				createElement( Layout, { post, hideTitle } )
			)
		);
	} catch ( error ) {
		// Fallback to the local editor and display a notice. Because the remote
		// editor loading failed, it is more practical to rely upon the local
		// editor's scripts and styles for displaying the notice.
		window.location.href = 'index.html?error=remote_editor_load_error';
	}
}

/**
 * Load the asset files for a block
 *
 * @param {string} html The HTML content to parse for assets.
 */
async function loadAssets( html ) {
	const excludedScriptIDs = new RegExp(
		localGutenbergPackages
			.map( ( script ) => `wp-${ script }-js` )
			.join( '|' )
	);
	const doc = new window.DOMParser().parseFromString( html, 'text/html' );

	const newAssets = Array.from(
		doc.querySelectorAll( 'link[rel="stylesheet"],script' )
	).filter( ( asset ) => asset.id && ! excludedScriptIDs.test( asset.id ) );

	/*
	 * Load each asset in order, as they may depend upon an earlier loaded script.
	 * Stylesheets and Inline Scripts will resolve immediately upon insertion.
	 */
	for ( const newAsset of newAssets ) {
		await loadAsset( newAsset );
	}
}

/**
 * Load an asset for a block.
 *
 * This function returns a Promise that will resolve once the asset is loaded,
 * or in the case of Stylesheets and Inline JavaScript, will resolve immediately.
 *
 * @param {HTMLElement} el A HTML Element asset to inject.
 *
 * @return {Promise} Promise which will resolve when the asset is loaded.
 */
function loadAsset( el ) {
	return new Promise( ( resolve ) => {
		/*
		 * Reconstruct the passed element, this is required as inserting the Node directly
		 * won't always fire the required onload events, even if the asset wasn't already loaded.
		 */
		const newNode = document.createElement( el.nodeName );

		[ 'id', 'rel', 'src', 'href', 'type' ].forEach( ( attr ) => {
			if ( el[ attr ] ) {
				newNode[ attr ] = el[ attr ];
			}
		} );

		// Append inline <script> contents.
		if ( el.innerHTML ) {
			newNode.appendChild( document.createTextNode( el.innerHTML ) );
		}

		newNode.onload = () => resolve( true );
		newNode.onerror = () => {
			// TODO: Communicate the error to the user.
			resolve( false );
		};

		document.body.appendChild( newNode );

		// Resolve Stylesheets and Inline JavaScript immediately.
		if (
			'link' === newNode.nodeName.toLowerCase() ||
			( 'script' === newNode.nodeName.toLowerCase() && ! newNode.src )
		) {
			resolve();
		}
	} );
}
