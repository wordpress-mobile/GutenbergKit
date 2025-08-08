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
			external,
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

function external( id ) {
	const hasExternal = defaultRequestToExternal( id ) !== undefined;
	const isInlineCss = id.match( /\.css\?inline$/ );

	return hasExternal && ! isInlineCss;
}

/**
 * Transform code by replacing WordPress imports with global definitions.
 * E.g., `import { __ } from '@wordpress/i18n';` becomes `const { __ } = window.wp.i18n;`
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
		transform( code ) {
			const magicString = new MagicString( code );
			let hasReplacements = false;

			// Match WordPress and React JSX runtime import statements
			const regex =
				/import\s*(?:(?:(\w+)|{([^}]+)})\s*from\s*)?['"](@wordpress\/[^'"]+|react\/jsx-runtime)['"];/g;
			let match;

			while ( ( match = regex.exec( code ) ) !== null ) {
				const [ fullMatch, defaultImport, namedImports, module ] =
					match;
				const imports = defaultImport || namedImports;

				if ( module.match( /\.css\?inline$/ ) ) {
					continue; // Exclude inlined CSS files from externalization
				}

				const externalDefinition = defaultRequestToExternal( module );

				if ( ! externalDefinition ) {
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
