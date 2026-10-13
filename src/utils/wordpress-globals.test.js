import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { camelCaseDash } from '@wordpress/dependency-extraction-webpack-plugin/lib/util';

// Packages flagged `wpScript` that WP Admin's post editor doesn't expose,
// keyed to the reason.
const EXCLUDED_PACKAGES = {
	'@wordpress/base-styles':
		'Flagged only to build its stylesheet; the editor never loads its empty script.',
};

// Modules that assign `window.wp` globals. Importing them would load every
// `@wordpress` package, which Node can't evaluate, so read their source.
const GLOBALS_MODULES = [ './wordpress-globals.js', './wordpress-i18n.js' ];

const SCRIPT_PACKAGES = getInstalledScriptPackages();

describe( 'WordPress globals', () => {
	const assignments = getAssignments();
	const exposedPackages = SCRIPT_PACKAGES.filter(
		( { name } ) => ! EXCLUDED_PACKAGES[ name ]
	).map( ( scriptPackage ) => [ scriptPackage.name, scriptPackage ] );

	// WordPress builds a `window.wp` global for each package flagged `wpScript`,
	// so the flag approximates the globals plugins expect. A missing global
	// breaks every plugin script that reads it.
	it.each( exposedPackages )( 'exposes %s', ( _name, { global } ) => {
		expect( assignments ).toHaveProperty( global );
	} );

	// Core exposes the default export of packages flagged
	// `wpScriptDefaultExport`, and the module namespace of the rest.
	it.each( exposedPackages )(
		'exposes %s in the shape core does',
		( _name, { global, defaultExport } ) => {
			expect( assignments[ global ] ).toMatch(
				defaultExport
					? /^(\w+)\.default \|\| \1$/
					: /^toCommonJS\( \w+ \)$|^undefined$/
			);
		}
	);

	it.each( Object.keys( EXCLUDED_PACKAGES ) )(
		'excludes %s only while it is flagged `wpScript`',
		( name ) => {
			expect( SCRIPT_PACKAGES ).toContainEqual(
				expect.objectContaining( { name } )
			);
		}
	);
} );

/**
 * List the installed `@wordpress` packages that WordPress builds as scripts.
 *
 * @return {Array<{name: string, global: string, defaultExport: boolean}>}
 *         Packages, with the `window.wp` member core assigns each.
 */
function getInstalledScriptPackages() {
	const root = join( import.meta.dirname, '../../node_modules/@wordpress' );

	// Skip entries that aren't packages, e.g. `.DS_Store` or npm's temporary
	// directories from an interrupted install.
	return readdirSync( root )
		.filter( ( directory ) =>
			existsSync( join( root, directory, 'package.json' ) )
		)
		.map( ( directory ) => [
			directory,
			JSON.parse(
				readFileSync( join( root, directory, 'package.json' ) )
			),
		] )
		.filter( ( [ , packageJson ] ) => packageJson.wpScript )
		.map( ( [ directory, packageJson ] ) => ( {
			name: packageJson.name,
			global: camelCaseDash( directory ),
			defaultExport: !! packageJson.wpScriptDefaultExport,
		} ) );
}

/**
 * Map each `window.wp` member the globals modules assign to its value's source.
 *
 * @return {Object<string, string>} Source keyed by global, e.g.
 *                                  `{ blockEditor: 'toCommonJS( blockEditor )' }`.
 */
function getAssignments() {
	return Object.fromEntries(
		GLOBALS_MODULES.flatMap( ( path ) => {
			const source = readFileSync(
				join( import.meta.dirname, path ),
				'utf8'
			);
			return [
				...source.matchAll( /window\.wp\.(\w+)\s*=\s*([^;]+);/g ),
			].map( ( [ , global, value ] ) => [
				global,
				value.replace( /\s+/g, ' ' ).trim(),
			] );
		} )
	);
}
