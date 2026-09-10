/**
 * Compares this repository's Android toolchain with WordPress-Android's and
 * reconciles a single tracking issue. Run by
 * `.github/workflows/android-toolchain-sync.yml`.
 */

/**
 * External dependencies
 */
import { readFile } from 'fs/promises';

const UPSTREAM = 'wordpress-mobile/WordPress-Android';
const UPSTREAM_REF = 'trunk';
const ISSUE_TITLE = 'Android toolchain drift with WordPress-Android';

// `local` and `upstream` name the same version in each repository's catalog;
// the keys differ between them. `blocking` marks versions that break the
// composite build outright, as opposed to ones worth reporting.
const TRACKED = [
	{ name: 'AGP', local: 'agp', upstream: 'agp', blocking: true },
	{
		name: 'Kotlin',
		local: 'kotlin',
		upstream: 'kotlin-main',
		blocking: true,
	},
];

/**
 * Opens, updates, or closes the drift issue to match the current versions.
 *
 * @param {Object} options
 * @param {Object} options.github  Authenticated Octokit client.
 * @param {Object} options.context Workflow run context.
 * @param {Object} options.core    GitHub Actions toolkit.
 */
export default async function reportToolchainDrift( {
	github,
	context,
	core,
} ) {
	const localCatalog = await readFile(
		'android/gradle/libs.versions.toml',
		'utf8'
	);
	const upstreamCatalog = await fetchUpstream(
		github,
		'gradle/libs.versions.toml'
	);

	const rows = TRACKED.map( ( entry ) => ( {
		name: entry.name,
		blocking: entry.blocking,
		ours: readCatalogVersion( localCatalog, entry.local, 'GutenbergKit' ),
		theirs: readCatalogVersion( upstreamCatalog, entry.upstream, UPSTREAM ),
	} ) );

	// Gradle itself is reported but never blocking: a composite build runs on
	// the root build's wrapper, so this only matters if GutenbergKit starts
	// requiring a newer Gradle than WordPress-Android provides.
	rows.push( {
		name: 'Gradle',
		blocking: false,
		ours: await readGradleVersion(
			readFile(
				'android/gradle/wrapper/gradle-wrapper.properties',
				'utf8'
			),
			'GutenbergKit',
			core
		),
		theirs: await readGradleVersion(
			fetchUpstream( github, 'gradle/wrapper/gradle-wrapper.properties' ),
			UPSTREAM,
			core
		),
	} );

	for ( const row of rows ) {
		core.info( `${ row.name }: ours=${ row.ours } theirs=${ row.theirs }` );
	}

	const drifted = rows.filter(
		( row ) => row.blocking && row.ours !== row.theirs
	);

	const { owner, repo } = context.repo;
	const openIssues = await github.paginate( github.rest.issues.listForRepo, {
		owner,
		repo,
		state: 'open',
		per_page: 100,
	} );
	const existing = openIssues.find(
		( issue ) => ! issue.pull_request && issue.title === ISSUE_TITLE
	);

	if ( drifted.length === 0 ) {
		core.info( 'Toolchain versions are in sync.' );
		if ( existing ) {
			await github.rest.issues.createComment( {
				owner,
				repo,
				issue_number: existing.number,
				body: 'Versions are back in sync with WordPress-Android. Closing.',
			} );
			await github.rest.issues.update( {
				owner,
				repo,
				issue_number: existing.number,
				state: 'closed',
			} );
		}
		return;
	}

	const table = [
		'| Version | GutenbergKit | WordPress-Android | |',
		'| --- | --- | --- | --- |',
		...rows.map(
			( row ) =>
				`| ${ row.name } | ${ formatVersion(
					row.ours
				) } | ${ formatVersion( row.theirs ) } | ${ formatStatus(
					row
				) } |`
		),
	].join( '\n' );

	const agp = rows.find( ( row ) => row.name === 'AGP' );
	const body = [
		`[${ UPSTREAM }](https://github.com/${ UPSTREAM }/blob/${ UPSTREAM_REF }/gradle/libs.versions.toml)` +
			' has moved ahead of this repository.',
		'',
		table,
		'',
		'Until these match, `./gradlew` in WordPress-Android fails during configuration for',
		'anyone who sets `localGutenbergKitPath` in `local-builds.gradle`:',
		'',
		'```',
		`Using multiple versions of the Android Gradle Plugin [${ agp.theirs }, ${ agp.ours }] across Gradle builds is not allowed.`,
		'Affected builds: [:, :android].',
		'```',
		'',
		'Update `android/gradle/libs.versions.toml` to the WordPress-Android versions above.',
		'Note that AGP upgrades have needed source changes beyond the version bump.',
		'',
		`<sub>Opened by [\`${ context.workflow }\`](https://github.com/${ owner }/${ repo }/blob/trunk/.github/workflows/android-toolchain-sync.yml).</sub>`,
	].join( '\n' );

	if ( existing ) {
		// GitHub stores issue bodies with CRLF line endings.
		if ( ( existing.body ?? '' ).replace( /\r\n/g, '\n' ) === body ) {
			core.info( `Issue #${ existing.number } is already up to date.` );
			return;
		}
		await github.rest.issues.update( {
			owner,
			repo,
			issue_number: existing.number,
			body,
		} );
		core.info( `Updated issue #${ existing.number }.` );
		return;
	}

	const created = await github.rest.issues.create( {
		owner,
		repo,
		title: ISSUE_TITLE,
		body,
		labels: [ 'Android', '[Type] Build Tooling' ],
	} );
	core.info( `Opened issue #${ created.data.number }.` );
}

/**
 * Reads a file from WordPress-Android's tracked branch.
 *
 * @param {Object} github Authenticated Octokit client.
 * @param {string} path   Repository-relative file path.
 * @return {Promise<string>} The file contents.
 */
async function fetchUpstream( github, path ) {
	const [ owner, repo ] = UPSTREAM.split( '/' );
	try {
		const { data } = await github.rest.repos.getContent( {
			owner,
			repo,
			path,
			ref: UPSTREAM_REF,
			mediaType: { format: 'raw' },
		} );
		return data;
	} catch ( error ) {
		throw new Error(
			`Could not read ${ path } from ${ UPSTREAM }@${ UPSTREAM_REF }: ${ error.message }`
		);
	}
}

/**
 * Reads a version from a Gradle version catalog.
 *
 * Lookups are confined to `[versions]` so a key is never matched against a
 * `version.ref` in `[plugins]`.
 *
 * @param {string} toml   Catalog contents.
 * @param {string} key    Key under `[versions]`.
 * @param {string} source Repository name for error messages.
 * @return {string} The version.
 */
function readCatalogVersion( toml, key, source ) {
	const lines = toml.split( '\n' );
	const start = lines.findIndex( ( line ) => line.trim() === '[versions]' );
	if ( start === -1 ) {
		throw new Error( `No [versions] section in ${ source }.` );
	}
	for ( const line of lines.slice( start + 1 ) ) {
		if ( line.trim().startsWith( '[' ) ) {
			break;
		}
		const entry = line.match( /^\s*(['"]?)([\w.-]+)\1\s*=(.*)$/ );
		if ( entry?.[ 2 ] !== key ) {
			continue;
		}
		// Either a plain version or a rich one, e.g. `{ strictly = "1.0" }`.
		const version = entry[ 3 ].match(
			/^\s*['"]([^'"]+)['"]|\b(?:strictly|require|prefer)\s*=\s*['"]([^'"]+)['"]/
		);
		if ( ! version ) {
			throw new Error(
				`Unrecognized '${ key }' version in ${ source }: ${ entry[ 3 ].trim() }`
			);
		}
		return version[ 1 ] ?? version[ 2 ];
	}
	throw new Error(
		`No '${ key }' entry under [versions] in ${ source }. ` +
			'The catalog key was probably renamed — update TRACKED in this script.'
	);
}

/**
 * Reads the Gradle wrapper version without failing the run. Gradle is only
 * reported, so an unreadable wrapper must not hide AGP or Kotlin drift.
 *
 * @param {Promise<string>} properties Wrapper properties contents.
 * @param {string}          source     Repository name for messages.
 * @param {Object}          core       GitHub Actions toolkit.
 * @return {Promise<string|null>} The Gradle version, or `null` if unreadable.
 */
async function readGradleVersion( properties, source, core ) {
	try {
		return readWrapperVersion( await properties, source );
	} catch ( error ) {
		core.warning( error.message );
		return null;
	}
}

/**
 * Reads the Gradle version from a wrapper properties file.
 *
 * @param {string} properties Wrapper properties contents.
 * @param {string} source     Repository name for error messages.
 * @return {string} The Gradle version.
 */
function readWrapperVersion( properties, source ) {
	const match = properties.match(
		/^\s*distributionUrl\s*=.*\/gradle-([^/]+)-(?:all|bin)\.zip\s*$/m
	);
	if ( ! match ) {
		throw new Error( `No distributionUrl version in ${ source }.` );
	}
	return match[ 1 ];
}

/**
 * @param {string|null} version A version, or `null` if unreadable.
 * @return {string} The table cell.
 */
function formatVersion( version ) {
	return version ? `\`${ version }\`` : 'unknown';
}

/**
 * @param {Object}      row          Version comparison.
 * @param {string|null} row.ours     GutenbergKit's version.
 * @param {string|null} row.theirs   WordPress-Android's version.
 * @param {boolean}     row.blocking Whether a mismatch breaks the composite build.
 * @return {string} The table status cell.
 */
function formatStatus( row ) {
	if ( ! row.ours || ! row.theirs ) {
		return 'could not be read';
	}
	if ( row.ours === row.theirs ) {
		return 'in sync';
	}
	return row.blocking ? '**drifted**' : 'differs (not blocking)';
}
