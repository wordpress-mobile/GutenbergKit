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
	const globals = getAssignedGlobals();

	// WordPress builds a `window.wp` global for each package flagged `wpScript`,
	// so the flag approximates the globals plugins expect. A missing global
	// breaks every plugin script that reads it.
	it.each(
		SCRIPT_PACKAGES.filter( ( name ) => ! EXCLUDED_PACKAGES[ name ] )
	)( 'exposes %s', ( name ) => {
		expect( globals ).toContain(
			camelCaseDash( name.replace( '@wordpress/', '' ) )
		);
	} );

	it.each( Object.keys( EXCLUDED_PACKAGES ) )(
		'excludes %s only while it is flagged `wpScript`',
		( name ) => {
			expect( SCRIPT_PACKAGES ).toContain( name );
		}
	);
} );

/**
 * List the installed `@wordpress` packages that WordPress builds as scripts.
 *
 * @return {string[]} Package names.
 */
function getInstalledScriptPackages() {
	const root = join( import.meta.dirname, '../../node_modules/@wordpress' );

	// Skip entries that aren't packages, e.g. `.DS_Store` or npm's temporary
	// directories from an interrupted install.
	return readdirSync( root )
		.filter( ( directory ) =>
			existsSync( join( root, directory, 'package.json' ) )
		)
		.filter( ( directory ) => {
			const packageJson = JSON.parse(
				readFileSync( join( root, directory, 'package.json' ) )
			);
			return packageJson.wpScript;
		} )
		.map( ( directory ) => `@wordpress/${ directory }` );
}

/**
 * List the `window.wp` members the globals modules assign.
 *
 * @return {string[]} Global names, e.g. `blockEditor`.
 */
function getAssignedGlobals() {
	return GLOBALS_MODULES.flatMap( ( path ) => {
		const source = readFileSync(
			join( import.meta.dirname, path ),
			'utf8'
		);
		return [ ...source.matchAll( /window\.wp\.(\w+)\s*=/g ) ].map(
			( [ , name ] ) => name
		);
	} );
}
