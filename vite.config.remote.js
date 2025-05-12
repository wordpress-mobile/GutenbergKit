/**
 * WordPress dependencies
 */
import { defaultRequestToExternal } from '@wordpress/dependency-extraction-webpack-plugin/lib/util';
import { nodePolyfills } from 'vite-plugin-node-polyfills';

/**
 * External dependencies
 */
import { resolve } from 'path';
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import MagicString from 'magic-string';

export default defineConfig( {
	base: '',
	build: {
		outDir: '../dist',
		rollupOptions: {
			input: resolve( __dirname, 'src/remote.html' ),
			external: externalize,
			output: {
				// Manual chunks are necessary to prevent circular dependencies, some of
				// which originate from Vite's injected helpers.
				//
				// See:
				// - https://github.com/vitejs/vite/issues/18551
				// - https://github.com/vitejs/vite/issues/13952
				// - https://github.com/vitejs/vite/issues/5189#issuecomment-2175410148
				manualChunks( id ) {
					const VITE_COMMON_MODULES = [
						'vite/preload-helper',
						'vite/modulepreload-polyfill',
						'vite/dynamic-import-helper',
						'commonjsHelpers',
						'commonjs-dynamic-modules',
						'__vite-browser-external',
					];
					if (
						VITE_COMMON_MODULES.some( ( m ) => id.includes( m ) )
					) {
						return 'vite-helpers';
					}

					if ( id.includes( 'src/utils/bridge.js' ) ) {
						return 'bridge';
					}

					if ( id.includes( 'src/utils/logger.js' ) ) {
						return 'logger';
					}
				},
			},
		},
		target: 'esnext',
	},
	plugins: [ nodePolyfills(), react(), wordPressExternals() ],
	root: 'src',
	css: {
		preprocessorOptions: {
			scss: {
				quietDeps: true,
			},
		},
	},
} );

function externalize( id ) {
	const externalDefinition = defaultRequestToExternal( id );
	return (
		!! externalDefinition &&
		! id.match( /\.css(?:\?inline)?$/ ) &&
		! [ 'apiFetch', 'i18n', 'url', 'hooks' ].includes(
			externalDefinition[ externalDefinition.length - 1 ]
		)
	);
}

/**
 * Transform code by replacing WordPress imports with global definitions.
 *
 * @return {Object} The transformed code and map.
 */
function wordPressExternals() {
	return {
		name: 'wordpress-externals-plugin',
		transform( code, id ) {
			const magicString = new MagicString( code );
			let hasReplacements = false;

			// Match WordPress and React JSX runtime import statements
			const regex =
				/import\s*(?:{([^}]+)}\s*from)?\s*['"](@wordpress\/([^'"]+)|react\/jsx-runtime)['"];/g;
			let match;

			while ( ( match = regex.exec( code ) ) !== null ) {
				const [ fullMatch, imports, module ] = match;
				const externalDefinition = defaultRequestToExternal( module );

				if (
					! externalDefinition ||
					/@wordpress\/(api-fetch|i18n|url)/.test( id )
				) {
					continue; // Exclude the module from externalization
				}

				hasReplacements = true;

				if ( ! imports ) {
					// Remove the side effect import entirely
					magicString.remove(
						match.index,
						match.index + fullMatch.length
					);
					continue;
				}

				const importList = imports.split( ',' ).map( ( i ) => {
					const parts = i.trim().split( /\s+as\s+/ );
					if ( parts.length === 2 ) {
						// Convert import "as" syntax to destructuring assignment
						return `${ parts[ 0 ] }: ${ parts[ 1 ] }`;
					}
					return i.trim();
				} );

				const definitionArray = Array.isArray( externalDefinition )
					? externalDefinition
					: [ externalDefinition ];

				const replacement = `const { ${ importList.join(
					', '
				) } } = window.${ definitionArray.join( '.' ) };`;
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
