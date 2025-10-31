/**
 * WordPress dependencies
 */
import { defaultRequestToExternal } from '@wordpress/dependency-extraction-webpack-plugin/lib/util';
import { nodePolyfills } from 'vite-plugin-node-polyfills';

/**
 * External dependencies
 */
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import MagicString from 'magic-string';

export default defineConfig( {
	base: '',
	build: {
		outDir: '../dist',
		rollupOptions: { external },
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
	// Exclude internal `@wordpress` module paths (e.g., /build-module/) from externalization
	if ( id.match( /\/build-module\// ) ) {
		return false;
	}
	const hasExternal = defaultRequestToExternal( id ) !== undefined;
	const isInlineCss = id.match( /\.css\?inline$/ );

	return hasExternal && ! isInlineCss;
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
		transform( code ) {
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
