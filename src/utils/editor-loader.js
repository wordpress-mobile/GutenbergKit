/**
 * Internal dependencies
 */
import { fetchEditorAssets } from './bridge';
import { error, warn } from './logger';

/**
 * Cache for editor assets to avoid unnecessary network requests
 * @type {Object|null}
 */
let editorAssetsCache = null;

/**
 * Handles that should be excluded because they're bundled in GutenbergKit
 * @type {Set<string>}
 */
const BUNDLED_HANDLES = new Set( [
	'react',
	'react-dom',
	'react-jsx-runtime',
	'lodash',
	'jquery',
	'jquery-core',
	'jquery-migrate',
	'moment',
	'regenerator-runtime',
] );

/**
 * Check if a script handle should be excluded (bundled in GutenbergKit)
 *
 * @param {string} handle Script handle to check
 * @return {boolean} True if the script should be excluded
 */
function shouldExcludeScript( handle ) {
	return handle.startsWith( 'wp-' ) || BUNDLED_HANDLES.has( handle );
}

/**
 * Fetch editor assets and load them into the page.
 * Assets are loaded in dependency order with inline scripts/styles
 * positioned correctly around their associated handles.
 */
export async function loadEditorAssets() {
	try {
		// Return cached response if available
		if ( editorAssetsCache ) {
			await processEditorAssets( editorAssetsCache );
			return;
		}

		const response = await fetchEditorAssets();

		// Cache the response
		editorAssetsCache = response;

		await processEditorAssets( response );
	} catch ( err ) {
		error( 'Error loading editor assets', err );
		throw err;
	}
}

/**
 * Process editor assets and load them into the page
 *
 * @param {Object} assets                The v2.1 assets to process
 * @param {Object} assets.scripts        Script assets keyed by handle
 * @param {Object} assets.styles         Style assets keyed by handle
 * @param {Object} assets.inline_scripts Inline scripts with before/after
 * @param {Object} assets.inline_styles  Inline styles with before/after
 */
async function processEditorAssets( assets ) {
	const {
		scripts = {},
		styles = {},
		inline_scripts: inlineScripts = {},
		inline_styles: inlineStyles = {},
	} = assets;

	// Filter out bundled scripts (but keep all styles)
	const filteredScripts = {};
	for ( const [ handle, data ] of Object.entries( scripts ) ) {
		if ( ! shouldExcludeScript( handle ) ) {
			filteredScripts[ handle ] = data;
		}
	}

	// Build dependency-ordered lists
	const orderedStyles = buildDependencyOrderedList( styles );
	const orderedScripts = buildDependencyOrderedList( filteredScripts );

	// Load stylesheets with inline styles
	for ( const handle of orderedStyles ) {
		// Inject "before" inline style
		const beforeInline = inlineStyles.before?.[ handle ];
		if ( beforeInline ) {
			injectInlineStyle( handle, beforeInline, 'before' );
		}

		// Load external stylesheet
		await loadStylesheet( handle, styles[ handle ] );

		// Inject "after" inline style
		const afterInline = inlineStyles.after?.[ handle ];
		if ( afterInline ) {
			injectInlineStyle( handle, afterInline, 'after' );
		}
	}

	// Prepare script elements (including inline scripts)
	const scriptElements = [];
	for ( const handle of orderedScripts ) {
		// Add "before" inline script
		const beforeInline = inlineScripts.before?.[ handle ];
		if ( beforeInline ) {
			scriptElements.push(
				createInlineScript( handle, beforeInline, 'before' )
			);
		}

		// Add external script
		scriptElements.push(
			createExternalScript( handle, filteredScripts[ handle ] )
		);

		// Add "after" inline script
		const afterInline = inlineScripts.after?.[ handle ];
		if ( afterInline ) {
			scriptElements.push(
				createInlineScript( handle, afterInline, 'after' )
			);
		}
	}

	// Load all scripts in order (parallel load with ordered execution)
	await performScriptLoad( scriptElements );
}

/**
 * Build a dependency-ordered list of asset handles using topological sort
 *
 * @param {Object} assetsData Assets keyed by handle with deps property
 * @return {string[]} Ordered list of handles
 */
function buildDependencyOrderedList( assetsData ) {
	const visited = new Set();
	const visiting = new Set();
	const orderedList = [];

	function visit( handle ) {
		if ( visited.has( handle ) ) {
			return;
		}
		if ( visiting.has( handle ) ) {
			warn( `Circular dependency detected for handle: ${ handle }` );
			return;
		}

		visiting.add( handle );

		if ( assetsData[ handle ] ) {
			const deps = assetsData[ handle ].deps || [];
			for ( const dep of deps ) {
				if ( assetsData[ dep ] ) {
					visit( dep );
				}
			}
		}

		visiting.delete( handle );
		visited.add( handle );

		if ( assetsData[ handle ] ) {
			orderedList.push( handle );
		}
	}

	for ( const handle of Object.keys( assetsData ) ) {
		visit( handle );
	}

	return orderedList;
}

/**
 * Load a stylesheet into the document head
 *
 * @param {string} handle    The stylesheet handle
 * @param {Object} styleData The stylesheet data with src, version, media
 * @return {Promise<void>} Resolves when loaded (or immediately if no src)
 */
function loadStylesheet( handle, styleData ) {
	return new Promise( ( resolve ) => {
		if ( ! styleData?.src ) {
			resolve();
			return;
		}

		const existingLink = document.getElementById( handle + '-css' );
		if ( existingLink ) {
			resolve();
			return;
		}

		const link = document.createElement( 'link' );
		link.rel = 'stylesheet';
		link.href = buildVersionedURL( styleData.src, styleData.version );
		link.id = handle + '-css';
		link.media = styleData.media || 'all';

		link.onload = () => resolve();
		link.onerror = () => {
			error( `Failed to load stylesheet: ${ handle }` );
			resolve();
		};

		document.head.appendChild( link );
	} );
}

/**
 * Inject an inline style into the document head
 *
 * @param {string}          handle      The associated stylesheet handle
 * @param {string|string[]} inlineStyle The inline CSS content
 * @param {string}          position    'before' or 'after'
 */
function injectInlineStyle( handle, inlineStyle, position ) {
	const styleContent = Array.isArray( inlineStyle )
		? inlineStyle.join( '\n' )
		: inlineStyle;

	if ( ! styleContent?.trim() ) {
		return;
	}

	const styleId = `${ handle }-${ position }-inline-css`;
	if ( document.getElementById( styleId ) ) {
		return;
	}

	const style = document.createElement( 'style' );
	style.id = styleId;
	style.textContent = styleContent.trim();
	document.head.appendChild( style );
}

/**
 * Create an external script element (not yet appended to DOM)
 *
 * @param {string} handle     The script handle
 * @param {Object} scriptData The script data with src, version
 * @return {HTMLScriptElement} The script element
 */
function createExternalScript( handle, scriptData ) {
	const script = document.createElement( 'script' );
	script.id = handle + '-js';

	if ( scriptData?.src ) {
		script.src = buildVersionedURL( scriptData.src, scriptData.version );
		script.async = false; // Maintain execution order
	} else {
		// Mark as processed even if no external source
		script.textContent = '// Processed: ' + handle;
	}

	return script;
}

/**
 * Create an inline script element (not yet appended to DOM)
 *
 * @param {string}          handle       The associated script handle
 * @param {string|string[]} inlineScript The inline JavaScript content
 * @param {string}          position     'before' or 'after'
 * @return {HTMLScriptElement} The script element
 */
function createInlineScript( handle, inlineScript, position ) {
	const scriptContent = Array.isArray( inlineScript )
		? inlineScript.join( '\n' )
		: inlineScript;

	const script = document.createElement( 'script' );
	script.id = `${ handle }-${ position }-js`;
	script.textContent = scriptContent.trim();

	return script;
}

/**
 * Load script elements in order with parallel external loading
 *
 * External scripts are loaded in parallel with async=false (maintains order).
 * Inline scripts are executed after waiting for all prior external scripts.
 *
 * @param {HTMLScriptElement[]} scriptElements Scripts to load
 */
async function performScriptLoad( scriptElements ) {
	let parallel = [];

	for ( const scriptElement of scriptElements ) {
		if ( scriptElement.src ) {
			// External scripts can be loaded in parallel
			// They execute in DOM order due to async=false
			const loader = createPromiseWithResolvers();
			scriptElement.onload = () => loader.resolve();
			scriptElement.onerror = () => {
				error( `Failed to load script: ${ scriptElement.id }` );
				loader.resolve();
			};
			parallel.push( loader.promise );
		} else {
			// Inline script - wait for all external scripts first
			await Promise.all( parallel );
			parallel = [];
		}

		// Append to DOM (triggers load for external, executes inline immediately)
		document.body.appendChild( scriptElement );
	}

	// Wait for any remaining external scripts
	await Promise.all( parallel );
}

/**
 * Build a URL with version query parameter
 *
 * @param {string}             src     The asset URL
 * @param {string|number|null} version The version string or number
 * @return {string} URL with version query parameter if applicable
 */
function buildVersionedURL( src, version ) {
	if ( ! version ) {
		return src;
	}
	// Handle version objects (StringOrBool from Swift)
	const versionStr =
		typeof version === 'object' ? version.string || version.int : version;
	if ( ! versionStr ) {
		return src;
	}
	return src + ( src.includes( '?' ) ? '&' : '?' ) + 'ver=' + versionStr;
}

/**
 * Create a promise with externally accessible resolve/reject functions
 * (Polyfill for Promise.withResolvers which may not be available)
 *
 * @return {Object} Object with promise, resolve, and reject properties
 */
function createPromiseWithResolvers() {
	let resolve, reject;
	const promise = new Promise( ( res, rej ) => {
		resolve = res;
		reject = rej;
	} );
	return { promise, resolve, reject };
}
