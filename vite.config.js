/**
 * External dependencies
 */
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import MagicString from 'magic-string';

/**
 * WordPress dependencies
 */
import { defaultRequestToExternal } from '@wordpress/dependency-extraction-webpack-plugin/lib/util';

// Stub for Node.js modules imported by PostCSS via @wordpress/block-editor.
// PostCSS marks these as `false` in its `browser` field, but the direct file
// path imports (e.g., `postcss/lib/processor`) bypass that field.
const nodeModuleStub = new URL( './src/stubs/node-modules.js', import.meta.url )
	.pathname;

export default defineConfig( {
	base: '',
	build: {
		outDir: '../dist',
		target: 'esnext',
		// Emit source maps so build tooling can upload them to Sentry for
		// exception symbolication. `'hidden'` writes the `.map` files but omits
		// the `//# sourceMappingURL=` comment from the shipped JS: the maps are
		// stripped from the native bundles (see the Makefile) so a comment
		// pointing at them would dangle. Dev-server debugging is unaffected —
		// `build.sourcemap` applies only to production builds, not `vite dev`.
		sourcemap: 'hidden',
	},
	resolve: {
		alias: {
			path: nodeModuleStub,
			fs: nodeModuleStub,
			url: nodeModuleStub,
			'source-map-js': nodeModuleStub,
		},
	},
	plugins: [
		react(),
		wordPressExternals(),
		reactDevTools(),
		emitSupportedLocalesManifest(),
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

			// Skip files that set up WordPress globals — they must import
			// the actual modules from node_modules, not read from window.wp.
			if (
				id.includes( 'wordpress-globals' ) ||
				id.includes( 'wordpress-i18n' )
			) {
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

				if ( module.match( /\.css\?(inline|raw)$/ ) ) {
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

/**
 * Emit `supported-locales.json` to the build output.
 *
 * Scans `src/translations/` for `<locale>.json` files at build time and emits
 * a single manifest listing every shipped locale tag. The native iOS and
 * Android sides — and the JS-side resolver — all read this manifest so the
 * "what do we actually ship?" answer has exactly one source of truth.
 *
 * @return {Object} Vite plugin configuration.
 */
function emitSupportedLocalesManifest() {
	const translationsDir = path.resolve(
		path.dirname( fileURLToPath( import.meta.url ) ),
		'src/translations'
	);

	function readSupportedLocales() {
		if ( ! fs.existsSync( translationsDir ) ) {
			return [];
		}
		return fs
			.readdirSync( translationsDir )
			.filter( ( f ) => f.endsWith( '.json' ) )
			.map( ( f ) => f.replace( /\.json$/, '' ) )
			.sort();
	}

	return {
		name: 'emit-supported-locales',
		apply: 'build',
		generateBundle() {
			this.emitFile( {
				type: 'asset',
				fileName: 'supported-locales.json',
				source: JSON.stringify( readSupportedLocales() ),
			} );
		},
	};
}

/**
 * Inject React Developer Tools connection script during development.
 * Only active when running the dev server, not in production builds.
 *
 * When the editor loads with ?dev_mode=1, it will connect to the standalone
 * React DevTools server at http://localhost:8097.
 *
 * @return {Object} Vite plugin configuration
 */
function reactDevTools() {
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
