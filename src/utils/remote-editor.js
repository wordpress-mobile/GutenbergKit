/**
 * WordPress dependencies
 */
import apiFetch from '@wordpress/api-fetch';

/**
 * Internal dependencies
 */
import { getGBKit } from './bridge';
import { error } from './logger';

/**
 * @typedef {Object} EditorAssetConfig
 *
 * @property {string[]} allowedBlockTypes Array of allowed block types provided by the API.
 * @property {Object}   wpDependencies    WordPress dependencies, empty when allowedPackages is provided.
 */

/**
 * Fetch editor assets and return select WordPress dependencies.
 *
 * @param {Object} [options]                    Options for the fetch.
 * @param {Array}  [options.allowedPackages]    Array of allowed package names to load.
 * @param {Array}  [options.disallowedPackages] Array of disallowed package names to load.
 *
 * @return {EditorAssetConfig} Allowed block types and WordPress dependencies.
 */
export async function loadEditorAssets( {
	allowedPackages = [],
	disallowedPackages = [],
} = {} ) {
	try {
		const { siteApiRoot, siteApiNamespace } = getGBKit();
		// TODO: Load editor assets within the host app
		const {
			styles,
			scripts,
			allowed_block_types: allowedBlockTypes,
		} = await apiFetch( {
			url: `${ siteApiRoot }wpcom/v2/${ siteApiNamespace[ 0 ] }/editor-assets`,
		} );

		if ( allowedPackages.length > 0 ) {
			// Only load allowed packages.
			await loadAssets( [ ...styles, ...scripts ].join( '' ), {
				allowedPackages,
			} );

			return {
				allowedBlockTypes,
				wpDependencies: {},
			};
		}

		await loadAssets( [ ...styles, ...scripts ].join( '' ), {
			disallowedPackages,
		} );

		return {
			allowedBlockTypes,
			wpDependencies: {
				StrictMode: window.wp?.element?.StrictMode,
				createRoot: window.wp?.element?.createRoot,
				dispatch: window.wp?.data?.dispatch,
				editorStore: window.wp?.editor?.store,
				preferencesStore: window.wp?.preferences?.store,
				registerCoreBlocks: window.wp?.blockLibrary?.registerCoreBlocks,
			},
		};
	} catch ( err ) {
		error( 'Error loading editor assets', err );
		// Fallback to the local editor and display a notice. Because the remote
		// editor loading failed, it is more practical to rely upon the local
		// editor's scripts and styles for displaying the notice.
		window.location.href = 'index.html?error=remote_editor_load_error';
	}
}

/**
 * Load the asset files for a block
 *
 * @param {string}   html                         The HTML content to parse for assets.
 * @param {Object}   [options]                    Options for the load.
 * @param {string[]} [options.allowedPackages]    Array of allowed package names to load.
 * @param {string[]} [options.disallowedPackages] Array of disallowed package names to load.
 */
async function loadAssets(
	html,
	{ allowedPackages = [], disallowedPackages = [] } = {}
) {
	/**
	 * Locally-sourced Gutenberg packages excluded from remote loading to avoid
	 * conflicts.
	 */
	const localGutenbergPackages = [ 'api-fetch', ...disallowedPackages ];

	const excludedScriptIDs = new RegExp(
		localGutenbergPackages
			.map( ( script ) => `wp-${ script }-js` )
			.join( '|' )
	);

	const allowedScriptIDs = allowedPackages.length
		? new RegExp(
				allowedPackages.map( ( pkg ) => `wp-${ pkg }-js` ).join( '|' )
		  )
		: null;

	const doc = new window.DOMParser().parseFromString( html, 'text/html' );

	const newAssets = Array.from(
		doc.querySelectorAll( 'link[rel="stylesheet"],script' )
	).filter( ( asset ) => {
		if ( ! asset.id ) {
			return false;
		}
		if ( allowedScriptIDs ) {
			return allowedScriptIDs.test( asset.id );
		}
		return ! excludedScriptIDs.test( asset.id );
	} );

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
