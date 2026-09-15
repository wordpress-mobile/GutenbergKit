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
// Starts every tracking issue's body, so the issue is found even if retitled.
const ISSUE_MARKER = '<!-- android-toolchain-sync';

// `local` and `upstream` name the same version in each repository's catalog;
// the keys differ between them. `blocking` marks versions the composite build
// needs to match, and `impact` describes what goes wrong when they don't.
const TRACKED = [
	{
		name: 'AGP',
		local: 'agp',
		upstream: 'agp',
		blocking: true,
		impact: ( { ours, theirs } ) => [
			'**AGP:** `./gradlew` in WordPress-Android fails during configuration:',
			'',
			'```',
			`Using multiple versions of the Android Gradle Plugin [${ theirs }, ${ ours }] across Gradle builds is not allowed.`,
			'Affected builds: [:, :android].',
			'```',
		],
	},
	{
		name: 'Kotlin',
		local: 'kotlin',
		upstream: 'kotlin-main',
		blocking: true,
		impact: () => [
			'**Kotlin:** the build still configures, but the newer Kotlin Gradle plugin silently wins the classpath for both builds, so one of them compiles with a Kotlin version it is not tested against.',
		],
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
		...entry,
		ours: readCatalogVersion( localCatalog, entry.local, 'GutenbergKit' ),
		theirs: readCatalogVersion( upstreamCatalog, entry.upstream, UPSTREAM ),
	} ) );

	// Gradle alone never opens an issue, since a composite build runs on the
	// root build's wrapper. It is still reported because each AGP release
	// requires a minimum Gradle version that this repository's build must meet.
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
	// Newest first, so the first match is the most recent tracking issue.
	const issues = await github.paginate( github.rest.issues.listForRepo, {
		owner,
		repo,
		state: 'all',
		creator: 'github-actions[bot]',
		per_page: 100,
	} );
	const tracking = issues.filter(
		( issue ) =>
			! issue.pull_request &&
			normalizeBody( issue.body ).startsWith( ISSUE_MARKER )
	);
	const existing = tracking.find( ( issue ) => issue.state === 'open' );

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
				state_reason: 'completed',
			} );
		}
		return;
	}

	const marker = issueMarker( drifted );
	const body = `${ marker }\n${ buildIssueBody( rows, drifted, context ) }`;

	if ( existing ) {
		if ( normalizeBody( existing.body ) === body ) {
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

	const [ latest ] = tracking;
	if (
		latest?.state_reason === 'not_planned' &&
		normalizeBody( latest.body ).startsWith( `${ marker }\n` )
	) {
		core.info(
			`Issue #${ latest.number } was closed as not planned for these versions.`
		);
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
 * GitHub stores issue bodies with CRLF line endings.
 *
 * @param {string|null} body Issue body from the API.
 * @return {string} The body with LF line endings.
 */
function normalizeBody( body ) {
	return ( body ?? '' ).replace( /\r\n/g, '\n' );
}

/**
 * @param {Object[]} drifted The tracked versions that differ.
 * @return {string} A hidden comment identifying the issue and its versions.
 */
function issueMarker( drifted ) {
	const versions = drifted.map(
		( row ) => `${ row.name }=${ row.ours }/${ row.theirs }`
	);
	return `${ ISSUE_MARKER } ${ versions.join( ' ' ) } -->`;
}

/**
 * @param {Object[]} rows    Every compared version.
 * @param {Object[]} drifted The tracked versions that differ.
 * @param {Object}   context Workflow run context.
 * @return {string} The issue body.
 */
function buildIssueBody( rows, drifted, context ) {
	const { owner, repo } = context.repo;
	const lines = [
		`This repository's Android toolchain no longer matches [${ UPSTREAM }](https://github.com/${ UPSTREAM }/blob/${ UPSTREAM_REF }/gradle/libs.versions.toml).`,
		'',
		'| Version | GutenbergKit | WordPress-Android | |',
		'| --- | --- | --- | --- |',
		...rows.map( formatRow ),
		'',
		"For anyone who sets `localGutenbergKitPath` in WordPress-Android's `local-builds.gradle`:",
		'',
		...drifted.flatMap( ( row ) => [ ...row.impact( row ), '' ] ),
		'Align `android/gradle/libs.versions.toml` with WordPress-Android. If this repository is ahead, WordPress-Android needs the same upgrade instead.',
	];

	if ( drifted.some( ( row ) => row.name === 'AGP' ) ) {
		lines.push(
			'AGP upgrades have needed source changes beyond the version bump.'
		);
		const gradle = rows.find( ( row ) => row.name === 'Gradle' );
		if ( gradle.theirs && gradle.ours !== gradle.theirs ) {
			lines.push(
				`Each AGP release also requires a minimum Gradle version, so update \`android/gradle/wrapper/gradle-wrapper.properties\` alongside it; WordPress-Android uses Gradle \`${ gradle.theirs }\`.`
			);
		}
	}

	lines.push(
		'',
		'To defer this, close the issue as not planned. A new one opens only when these versions change.',
		'',
		`<sub>Opened by [\`${ context.workflow }\`](https://github.com/${ owner }/${ repo }/blob/trunk/.github/workflows/android-toolchain-sync.yml).</sub>`
	);
	return lines.join( '\n' );
}

/**
 * @param {Object}      row          Version comparison.
 * @param {string}      row.name     Toolchain component.
 * @param {string|null} row.ours     GutenbergKit's version.
 * @param {string|null} row.theirs   WordPress-Android's version.
 * @param {boolean}     row.blocking Whether the composite build needs a match.
 * @return {string} The Markdown table row.
 */
function formatRow( row ) {
	const cells = [
		row.name,
		formatVersion( row.ours ),
		formatVersion( row.theirs ),
		formatStatus( row ),
	];
	return `| ${ cells.join( ' | ' ) } |`;
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
 * @param {boolean}     row.blocking Whether the composite build needs a match.
 * @return {string} The table status cell.
 */
function formatStatus( row ) {
	if ( ! row.ours || ! row.theirs ) {
		return 'could not be read';
	}
	if ( row.ours === row.theirs ) {
		return 'in sync';
	}
	return row.blocking ? '**drifted**' : 'differs';
}
