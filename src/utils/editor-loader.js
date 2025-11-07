/**
 * Internal dependencies
 */
import { fetchEditorAssets } from './bridge';
import { error, warn } from './logger';
import { isDevMode } from './dev-mode';

/**
 * Cache for editor assets to avoid unnecessary network requests
 * @type {Object|null}
 */
let editorAssetsCache = null;

/**
 * @typedef {Object} EditorAssetConfig
 *
 * @property {string[]} allowedBlockTypes Array of allowed block types provided by the API.
 */

/**
 * Fetch editor assets and return select WordPress dependencies.
 *
 * @param {Object} [options]                    Options for the fetch.
 * @param {Array}  [options.allowedPackages]    Array of allowed package names to load.
 * @param {Array}  [options.disallowedPackages] Array of disallowed package names to load.
 *
 * @return {EditorAssetConfig} Editor configuration provided by the API.
 */
export async function loadEditorAssets( {
	allowedPackages = [],
	disallowedPackages = [],
} = {} ) {
	try {
		// Return cached response if available
		if ( editorAssetsCache ) {
			return processEditorAssets( editorAssetsCache, {
				allowedPackages,
				disallowedPackages,
			} );
		}

		const response = await fetchEditorAssets();

		// Cache the response
		editorAssetsCache = response;

		return processEditorAssets( response, {
			allowedPackages,
			disallowedPackages,
		} );
	} catch ( err ) {
		error( 'Error loading editor assets', err );
		if ( isDevMode() ) {
			warn( 'Dev mode disabled automatic redirect to the local editor.' );
		} else {
			// Fallback to the local editor and display a notice. Because the remote
			// editor loading failed, it is more practical to rely upon the local
			// editor's scripts and styles for displaying the notice.
			window.location.href = 'index.html?error=remote_editor_load_error';
		}
	}
}

/**
 * Process editor assets and return the configuration
 *
 * @param {Object}   assets                     The assets to process
 * @param {string[]} assets.styles              Array of style assets
 * @param {string[]} assets.scripts             Array of script assets
 * @param {string[]} assets.allowedBlockTypes   Array of allowed block types
 * @param {Object}   options                    Processing options
 * @param {string[]} options.allowedPackages    Array of allowed package names
 * @param {string[]} options.disallowedPackages Array of disallowed package names
 *
 * @return {EditorAssetConfig} Processed editor configuration
 */
async function processEditorAssets(
	assets,
	{ allowedPackages = [], disallowedPackages = [] } = {}
) {
	const { styles, scripts, allowed_block_types: allowedBlockTypes } = assets;

	if ( allowedPackages.length > 0 ) {
		await loadAssets( [ ...styles, ...scripts ].join( '' ), {
			allowedPackages,
		} );

		return { allowedBlockTypes };
	}

	await loadAssets( [ ...styles, ...scripts ].join( '' ), {
		disallowedPackages,
	} );

	return { allowedBlockTypes };
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
	const excludedScriptIDs = disallowedPackages.length
		? new RegExp(
				disallowedPackages
					.map( ( script ) => `wp-${ script }-js` )
					.join( '|' )
		  )
		: null;

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

		if ( excludedScriptIDs ) {
			return ! excludedScriptIDs.test( asset.id );
		}

		/**
		 * TODO: Remove this once the relevant Jetpack plugin release is available.
		 *
		 * Exclude WordPress core and Gutenberg assets to avoid loading duplicate
		 * assets, which causes editor loading failures.
		 *
		 * This is a temporary measure until users update to the latest Jetpack REST
		 * API endpoint that excludes these assets. This can be removed a few weeks
		 * after the relevant Jetpack plugin release.
		 *
		 * See: https://github.com/Automattic/jetpack/pull/45715
		 */
		const coreOrGutenbergRegex = new RegExp(
			'wp-(includes|admin)/(js|css)|plugins/gutenberg(-core)?/'
		);
		if ( coreOrGutenbergRegex.test( asset.src || asset.href ) ) {
			return false;
		}

		return true;
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
