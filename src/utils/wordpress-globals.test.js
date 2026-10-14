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
	const scriptNames = SCRIPT_PACKAGES.map( ( { name } ) => name );
	const scriptGlobals = SCRIPT_PACKAGES.map( ( { global } ) => global );

	// WordPress builds a `window.wp` global for each package flagged `wpScript`,
	// so the flag approximates the globals plugins expect. A missing global
	// breaks every plugin script that reads it. Core exposes the default export
	// of packages flagged `wpScriptDefaultExport`, and the namespace of the rest.
	it.each(
		SCRIPT_PACKAGES.filter( ( { name } ) => ! EXCLUDED_PACKAGES[ name ] )
	)(
		'exposes $name in the shape core does',
		( { global, defaultExport } ) => {
			expect( assignments ).toHaveProperty( global );
			expect( assignments[ global ] ).toMatch(
				defaultExport
					? /^(\w+)\.default \|\| \1$/
					: /^toCommonJS\( \w+ \)$|^undefined$/
			);
		}
	);

	// A global without a flagged package is one core no longer exposes, like
	// `wp.sync` after WordPress/gutenberg#81999.
	it.each( Object.keys( assignments ) )(
		'exposes window.wp.%s only while a package is flagged `wpScript`',
		( global ) => {
			expect( scriptGlobals ).toContain( global );
		}
	);

	it.each( Object.keys( EXCLUDED_PACKAGES ) )(
		'excludes %s only while it is flagged `wpScript`',
		( name ) => {
			expect( scriptNames ).toContain( name );
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

	return readdirSync( root ).flatMap( ( directory ) => {
		const path = join( root, directory, 'package.json' );

		// Skip entries that aren't packages, e.g. `.DS_Store` or npm's
		// temporary directories from an interrupted install.
		if ( ! existsSync( path ) ) {
			return [];
		}

		const { name, wpScript, wpScriptDefaultExport } = JSON.parse(
			readFileSync( path )
		);

		return wpScript
			? [
					{
						name,
						global: camelCaseDash( directory ),
						defaultExport: !! wpScriptDefaultExport,
					},
			  ]
			: [];
	} );
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
