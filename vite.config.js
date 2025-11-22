/**
 * External dependencies
 */
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { nodePolyfills } from 'vite-plugin-node-polyfills';
import MagicString from 'magic-string';

/**
 * WordPress dependencies
 */
import { defaultRequestToExternal } from '@wordpress/dependency-extraction-webpack-plugin/lib/util';

export default defineConfig( {
	base: '',
	build: {
		outDir: '../dist',
		target: 'esnext',
	},
	plugins: [
		nodePolyfills(),
		react(),
		wordPressExternals(),
		injectReactDevTools(),
	],
	root: 'src',
	css: {
		preprocessorOptions: {
			scss: {
				quietDeps: true,
			},
		},
	},
} );

/**
 * Inject React Developer Tools connection script during development.
 * Only active when running the dev server, not in production builds.
 *
 * When the editor loads with ?dev_mode=1, it will connect to the standalone
 * React DevTools server at http://localhost:8097.
 *
 * @return {Object} Vite plugin configuration
 */
function injectReactDevTools() {
	return {
		name: 'inject-react-devtools',
		transformIndexHtml: {
			order: 'pre',
			handler( html, ctx ) {
				// Only inject during dev server
				if ( ctx.server ) {
					return {
						html,
						tags: [
							{
								tag: 'script',
								attrs: { id: 'react-devtools-loader' },
								children: `
									// Connect to React DevTools standalone server if in dev mode
									if (new URLSearchParams(window.location.search).has('dev_mode')) {
										const script = document.createElement('script');
										script.src = 'http://localhost:8097';
										script.onerror = () => {
											console.warn('[GBK] Failed loading http://localhost:8097, ensure the React DevTools server is running.');
										};
										document.head.appendChild(script);
									}
								`,
								injectTo: 'head-prepend',
							},
						],
					};
				}
				return html;
			},
		},
	};
}

/**
 * Transform code by replacing WordPress imports with global definitions.
 * E.g., `import { __ } from '@wordpress/i18n';` becomes `const { __ } = window.wp.i18n;`
 * Also transforms dynamic imports: `await import('@wordpress/blocks')` becomes `Promise.resolve(window.wp.blocks)`
 * This replicates Gutenberg's behavior in a browser environment, which relies upon
 * the `@wordpress/dependency-extraction-webpack-plugin` module.
 *
 * See: https://github.com/WordPress/gutenberg/tree/d2fce222ebbbef8dbc56eee1badcfe4ae0df04b0/packages/dependency-extraction-webpack-plugin
 *
 * @return {Object} The transformed code and map.
 */
function wordPressExternals() {
	return {
		name: 'wordpress-externals-plugin',
		transform( code, id ) {
			// Skip transforming node_modules files
			if ( id.includes( 'node_modules' ) ) {
				return null;
			}

			const magicString = new MagicString( code );
			let hasReplacements = false;

			// Match static WordPress and React JSX runtime import statements
			const staticImportRegex =
				/import\s*(?:(?:(\w+)|{([^}]+)})\s*from\s*)?['"](@wordpress\/[^'"]+|react\/jsx-runtime)['"];/g;
			let match;

			while ( ( match = staticImportRegex.exec( code ) ) !== null ) {
				const [ fullMatch, defaultImport, namedImports, module ] =
					match;
				const imports = defaultImport || namedImports;

				if ( module.match( /\.css\?inline$/ ) ) {
					continue; // Exclude inlined CSS files from externalization
				}

				// Exclude internal `@wordpress` module paths (e.g., /build-module/)
				// from externalization.
				if ( module.match( /\/build-module\// ) ) {
					continue;
				}

				const externalDefinition = defaultRequestToExternal( module );

				if ( ! externalDefinition ) {
					continue; // Exclude the module from externalization
				}

				hasReplacements = true;

				if ( ! imports ) {
					// Preserve CSS side-effect imports
					if (
						module.endsWith( '.css' ) ||
						module.includes( '.css?' )
					) {
						continue;
					}

					// Remove non-CSS side effect imports
					magicString.remove(
						match.index,
						match.index + fullMatch.length
					);
					continue;
				}

				const definitionArray = Array.isArray( externalDefinition )
					? externalDefinition
					: [ externalDefinition ];

				let replacement;
				if ( defaultImport ) {
					// Handle default import
					replacement = `const ${ defaultImport } = window.${ definitionArray.join(
						'.'
					) };`;
				} else {
					// Handle named imports
					const importList = imports.split( ',' ).map( ( i ) => {
						const parts = i.trim().split( /\s+as\s+/ );
						if ( parts.length === 2 ) {
							// Convert import "as" syntax to destructuring assignment
							return `${ parts[ 0 ] }: ${ parts[ 1 ] }`;
						}
						return i.trim();
					} );

					replacement = `const { ${ importList.join(
						', '
					) } } = window.${ definitionArray.join( '.' ) };`;
				}
				magicString.overwrite(
					match.index,
					match.index + fullMatch.length,
					replacement
				);
			}

			// Match dynamic WordPress imports
			const dynamicImportRegex =
				/import\s*\(\s*['"](@wordpress\/[^'"]+)['"]\s*\)/g;

			while ( ( match = dynamicImportRegex.exec( code ) ) !== null ) {
				const [ fullMatch, module ] = match;

				// Exclude internal `@wordpress` module paths (e.g., /build-module/)
				// from externalization.
				if ( module.match( /\/build-module\// ) ) {
					continue;
				}

				const externalDefinition = defaultRequestToExternal( module );

				if ( ! externalDefinition ) {
					continue; // Exclude the module from externalization
				}

				hasReplacements = true;

				const definitionArray = Array.isArray( externalDefinition )
					? externalDefinition
					: [ externalDefinition ];

				// Transform to Promise that resolves with the global
				const replacement = `Promise.resolve(window.${ definitionArray.join(
					'.'
				) })`;

				magicString.overwrite(
					match.index,
					match.index + fullMatch.length,
					replacement
				);
			}

			if ( ! hasReplacements ) {
				return null;
			}

			return {
				code: magicString.toString(),
				map: magicString.generateMap( { hires: true } ),
			};
		},
	};
}
