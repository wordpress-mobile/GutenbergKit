#!/usr/bin/env node

/**
 * Fail when any @wordpress package is installed more than once in the
 * production dependency graph.
 *
 * The editor exposes its @wordpress packages on `window.wp` for plugin
 * scripts, mirroring WP Admin. That only works when each package is a single
 * module instance: a second copy nested under another dependency brings its
 * own React contexts, data stores, and private APIs, and nothing at runtime
 * reports the split. `wordPressExternals()` in `vite.config.js` rewrites
 * source imports to `window.wp` but deliberately skips `node_modules`, so a
 * nested copy is bundled by path and does become a second instance.
 *
 * The lockfile is the source of truth rather than the installed tree: it
 * describes what a fresh `npm ci` produces, needs no `node_modules`, and its
 * install paths distinguish separate copies of the same version, which are
 * still separate module instances.
 */

/**
 * External dependencies
 */
import { readFileSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

/**
 * Internal dependencies
 */
import { error, info, warn } from '../src/utils/logger.js';

const rootDir = join( dirname( fileURLToPath( import.meta.url ) ), '..' );
const lockfilePath = join( rootDir, 'package-lock.json' );

const NODE_MODULES = 'node_modules/';

/**
 * Packages known to be installed more than once. Each entry should reference
 * the work that will remove it, and is reported as a warning so the debt stays
 * visible. An entry that no longer applies fails the check rather than
 * lingering to mask a future regression.
 */
const KNOWN_DUPLICATES = {
	// Dependabot bumped commands, components, and preferences past the
	// icons range required by block-editor and editor. Resolves once the
	// @wordpress packages are bumped together to a single release.
	'@wordpress/icons': true,
};

process.exitCode = checkForDuplicateInstalls();

/**
 * Report every @wordpress package the lockfile installs more than once, along
 * with any `KNOWN_DUPLICATES` entry that no longer applies.
 *
 * @return {number} Process exit code.
 */
function checkForDuplicateInstalls() {
	const lockfile = readLockfile();

	if ( ! lockfile ) {
		return 1;
	}

	const installsByPackage = collectWordPressPackageInstalls( lockfile );

	// A tree with no @wordpress packages means the lockfile is empty or in an
	// unexpected format. Passing here would make a check that examined nothing
	// indistinguishable from one that found nothing wrong.
	if ( installsByPackage.size === 0 ) {
		error(
			`No @wordpress packages found in ${ lockfilePath }. The lockfile is empty or in an unexpected format, so nothing was checked.`
		);
		return 1;
	}

	const staleAllowances = new Set(
		Object.keys( KNOWN_DUPLICATES ).filter( isKnownDuplicate )
	);
	let hasUnexpectedDuplicate = false;

	for ( const [ name, installs ] of installsByPackage ) {
		if ( installs.length < 2 ) {
			continue;
		}

		const message = `${ name } is installed ${
			installs.length
		} times: ${ describeInstalls( installs ) }`;

		if ( isKnownDuplicate( name ) ) {
			staleAllowances.delete( name );
			warn( `Known duplicate: ${ message }` );
		} else {
			hasUnexpectedDuplicate = true;
			error( message );
		}
	}

	if ( hasUnexpectedDuplicate ) {
		error(
			'Every @wordpress package must have a single install so window.wp exposes one instance. Bump the lagging package, or bump all @wordpress packages together.'
		);
		error(
			"When that has to wait -- a security advisory moving one package alone, say -- add it to this script's KNOWN_DUPLICATES with a link to the follow-up. That is a deliberate exception rather than a fix: the editor then ships a known split, and for a package holding a store, context, or registry, plugin scripts get a different instance than the editor's own components with nothing at runtime to signal it."
		);
	}

	for ( const name of staleAllowances ) {
		error(
			`${ name } is listed in KNOWN_DUPLICATES but is no longer duplicated. Remove the entry so it cannot mask a future regression.`
		);
	}

	if ( hasUnexpectedDuplicate || staleAllowances.size > 0 ) {
		return 1;
	}

	info(
		`Checked ${ installsByPackage.size } @wordpress packages; no unexpected duplicates.`
	);

	return 0;
}

/**
 * Read and parse the lockfile.
 *
 * @return {Object|undefined} Parsed lockfile, or undefined when it cannot be
 *                            read or parsed.
 */
function readLockfile() {
	let contents;

	try {
		contents = readFileSync( lockfilePath, 'utf8' );
	} catch ( readError ) {
		error( `Could not read ${ lockfilePath }: ${ readError.message }` );
		return undefined;
	}

	try {
		return JSON.parse( contents );
	} catch ( parseError ) {
		error( `Could not parse ${ lockfilePath }: ${ parseError.message }` );
		return undefined;
	}
}

/**
 * Map each @wordpress package to every place the lockfile installs it.
 *
 * The `packages` keys are install paths, so a nested copy is a distinct entry
 * even when it shares a version with the hoisted one. Development-only entries
 * are skipped because they never reach the bundle.
 *
 * @param {Object} lockfile Parsed `package-lock.json`.
 * @return {Map<string, Array<{path: string, version: string}>>} Package name to
 *                                                               its installs.
 */
function collectWordPressPackageInstalls( lockfile ) {
	const installs = new Map();

	for ( const [ path, entry ] of Object.entries( lockfile.packages || {} ) ) {
		if ( entry.dev || ! entry.version ) {
			continue;
		}

		const index = path.lastIndexOf( NODE_MODULES );

		if ( index === -1 ) {
			continue;
		}

		const name = path.slice( index + NODE_MODULES.length );

		if ( ! name.startsWith( '@wordpress/' ) ) {
			continue;
		}

		if ( ! installs.has( name ) ) {
			installs.set( name, [] );
		}

		installs.get( name ).push( { path, version: entry.version } );
	}

	return installs;
}

/**
 * Whether a package is currently allowed to be installed more than once.
 *
 * Membership alone is not enough: an entry set to a falsy value is treated as
 * removed, so that toggling one off reports the duplicate rather than claiming
 * the allowance went stale.
 *
 * @param {string} name Package name.
 * @return {boolean} True when the duplicate is allowed.
 */
function isKnownDuplicate( name ) {
	return Boolean( KNOWN_DUPLICATES[ name ] );
}

/**
 * Format installs as `version (path)` pairs so the nesting parent is visible.
 *
 * @param {Array<{path: string, version: string}>} installs Installs of a single
 *                                                          package.
 * @return {string} Human readable list of installs.
 */
function describeInstalls( installs ) {
	return installs
		.map( ( { path, version } ) => `${ version } (${ path })` )
		.join( ', ' );
}
