/**
 * Spike S4 (CMM-2559): inject save failures and check how they're classified.
 *
 * Throwaway code. Prototypes the §4.2 save controller around core `savePost()`
 * (refusals, a late `editor.preSavePost` filter with the conflict check, a
 * last `editor.savePost` action, and classification from core-data by
 * `{ type, id }`), plus a stand-in for the host journal (§4.4) kept in
 * `localStorage`. Renders a panel outside the editor's error boundary so it
 * survives the crash case, and exposes everything on `window.__s4` for
 * driving from Playwright, CDP or the WebKit inspector.
 */
/* eslint-disable jsdoc/require-param, jsdoc/check-param-names, @wordpress/no-unused-vars-before-return, react-refresh/only-export-components, no-bitwise */
import apiFetch from '@wordpress/api-fetch';
import { createBlock } from '@wordpress/blocks';
import { store as blockEditorStore } from '@wordpress/block-editor';
import { store as coreStore } from '@wordpress/core-data';
import { dispatch, select } from '@wordpress/data';
import { store as editorStore } from '@wordpress/editor';
import { useEffect, useState } from '@wordpress/element';
import { addAction, addFilter } from '@wordpress/hooks';
import { store as noticesStore } from '@wordpress/notices';
import { getGBKit, getPostPath, getPostReference } from './bridge';
import { info } from './logger';

const MODES = [ 'off', 'error500', 'slow90s', 'drop', 'conflict' ];
const MODE_PATH = '/gutenbergkit/v1/post-write-failure';
const JOURNAL_KEY = 's4.pending';

/** Error codes and statuses after which the server may have applied the write. */
const AMBIGUOUS_CODES = [
	'fetch_error',
	'invalid_json',
	'relay_upstream_failed',
];
const AMBIGUOUS_STATUSES = [ 502, 503, 504 ];

const s4 = {
	log: [],
	attempts: [],
	listeners: new Set(),
	crashArmed: false,
	mode: '?',
	conflictCheck: true,
	base: null,
	current: null,
	nextId: 1,
};
window.__s4 = s4;

function log( message, data ) {
	const entry = { t: clock(), message, data };
	s4.log.push( entry );
	info( `[s4] ${ message } ${ JSON.stringify( data ?? {} ) }` );
	s4.listeners.forEach( ( listener ) => listener() );
}

function clock() {
	return new Date().toISOString().slice( 11, 23 );
}

/**
 * FNV-1a over UTF-16 code units, so the shell can compare server content with
 * a snapshot without either side shipping the whole string.
 *
 * @param {string} value Text to hash.
 * @return {string} Eight hex digits.
 */
export function hash( value = '' ) {
	let h = 0x811c9dc5;
	for ( let i = 0; i < value.length; i++ ) {
		h ^= value.charCodeAt( i );
		h = Math.imul( h, 0x01000193 ) >>> 0;
	}
	return h.toString( 16 ).padStart( 8, '0' );
}

function postRef() {
	const reference = getPostReference( getGBKit().post );
	return { ...reference, path: getPostPath( reference ) };
}

// ---------------------------------------------------------------------------
// Request logger
// ---------------------------------------------------------------------------

apiFetch.use( async ( options, next ) => {
	const method = ( options.method ?? 'GET' ).toUpperCase();
	const target = ( options.path || options.url || '' ).split( '?' )[ 0 ];
	const { path } = postRef();
	if (
		method === 'GET' &&
		! target.startsWith( path ) &&
		! target.startsWith( MODE_PATH )
	) {
		return next( options );
	}
	const started = performance.now();
	log( `→ ${ method } ${ target }` );
	try {
		const response = await next( options );
		log( `← ${ method } ${ target } ok`, {
			ms: Math.round( performance.now() - started ),
			modifiedGmt: response?.modified_gmt,
		} );
		return response;
	} catch ( err ) {
		log( `← ${ method } ${ target } FAIL`, {
			ms: Math.round( performance.now() - started ),
			code: err?.code,
			status: err?.data?.status,
			message: err?.message,
		} );
		throw err;
	}
} );

// ---------------------------------------------------------------------------
// Save controller prototype (§4.2)
// ---------------------------------------------------------------------------

/**
 * Reads what would be sent, from core-data by `{ type, id }`.
 *
 * @param {Object} ref The post reference.
 * @return {Object} Title, content and excerpt.
 */
function readSnapshot( { type, id } ) {
	const record = select( coreStore ).getEditedEntityRecord(
		'postType',
		type,
		id
	);
	const content =
		typeof record?.content === 'function'
			? record.content( record )
			: record?.content ?? '';
	return {
		title: record?.title ?? '',
		content,
		excerpt: record?.excerpt ?? '',
	};
}

function captureBase( { type, id } ) {
	const record = select( coreStore ).getEntityRecord( 'postType', type, id );
	if ( record ) {
		s4.base = {
			modifiedGmt: record.modified_gmt,
			content: record.content?.raw,
		};
	}
	return s4.base;
}

function startAttempt( initiator, options = {} ) {
	const attempt = {
		attemptId: `s4-${ s4.nextId++ }`,
		initiator,
		isAutosave: !! options.isAutosave,
		startedAt: new Date().toISOString(),
		requestIssued: false,
		hooksSucceeded: false,
		abort: null,
	};
	s4.current = attempt;
	return attempt;
}

// Late priority, so it runs after every plugin's filter.
addFilter(
	'editor.preSavePost',
	'gbk/s4-controller',
	async ( edits, options ) => {
		const ref = postRef();
		const attempt = s4.current ?? startAttempt( 'editor', options );
		const snapshot = readSnapshot( ref );
		const base = s4.base ?? captureBase( ref );

		// §4.4 rule 1: the host backs up the snapshot and records it as pending
		// before replying. Here the page stands in for the host.
		journalWrite( {
			attemptId: attempt.attemptId,
			startedAt: attempt.startedAt,
			post: {
				id: ref.id,
				type: ref.type,
				restBase: ref.restBase,
				restNamespace: ref.restNamespace,
			},
			baseModifiedGmt: base?.modifiedGmt,
			snapshotHash: hash( snapshot.content ),
			snapshotLength: snapshot.content.length,
		} );
		log( 'onEditorWillSavePost', {
			attemptId: attempt.attemptId,
			initiator: attempt.initiator,
			isAutosave: !! options?.isAutosave,
			snapshotHash: hash( snapshot.content ),
		} );

		if ( s4.conflictCheck && base?.modifiedGmt ) {
			let server;
			try {
				// No `id` in `_fields`: GBK's persisted-post overlay replaces the
				// content of any response record carrying the post's ID.
				server = await apiFetch( {
					path: `${ ref.path }?context=edit&_fields=modified_gmt,content`,
				} );
			} catch ( err ) {
				attempt.abort = { reason: 'check_failed', code: err?.code };
				throw { code: 'check_failed', message: err?.message };
			}
			const serverContent = server?.content?.raw;
			const changed = server?.modified_gmt !== base.modifiedGmt;
			const differs =
				serverContent !== base.content &&
				serverContent !== snapshot.content;
			log( 'conflict check', {
				base: base.modifiedGmt,
				server: server?.modified_gmt,
				changed,
				contentDiffers: differs,
			} );
			if ( changed && differs ) {
				attempt.abort = {
					reason: 'conflict',
					serverModifiedGmt: server.modified_gmt,
				};
				throw {
					code: 'conflict',
					message: 'The post changed elsewhere.',
				};
			}
		}

		attempt.requestIssued = true;
		return edits;
	},
	1000
);

// Last priority: reached only when the write and every earlier hook succeeded.
addAction(
	'editor.savePost',
	'gbk/s4-controller',
	() => {
		if ( s4.current ) {
			s4.current.hooksSucceeded = true;
		}
	},
	1000
);

/**
 * Saves through core and classifies the outcome.
 *
 * @param {Object}  [options]
 * @param {boolean} [options.autosave] Autosave instead of a full save.
 * @return {Promise<Object>} The outcome, shaped like `onEditorSaveFinished`.
 */
export async function save( { autosave = false } = {} ) {
	const ref = postRef();
	const editor = select( editorStore );

	if ( ! ( ref.id > 0 ) ) {
		return finish( null, ref, {
			outcome: 'skipped',
			reason: 'no_server_id',
		} );
	}
	if ( ! editor.isEditedPostSaveable() ) {
		return finish( null, ref, {
			outcome: 'skipped',
			reason: 'not_saveable',
		} );
	}
	const locked = autosave
		? ! editor.isEditedPostAutosaveable()
		: editor.isPostSavingLocked();
	if ( locked ) {
		return finish( null, ref, { outcome: 'skipped', reason: 'locked' } );
	}

	if ( s4.current ) {
		return finish( null, ref, { outcome: 'skipped', reason: 'in_flight' } );
	}

	const attempt = startAttempt( 'host', { isAutosave: autosave } );
	log( 'save: start', { attemptId: attempt.attemptId, autosave } );
	try {
		await dispatch( editorStore )[ autosave ? 'autosave' : 'savePost' ]();
	} catch ( err ) {
		attempt.threw = err?.message ?? String( err );
	}
	s4.current = null;
	return finish( attempt, ref, classify( attempt, ref ) );
}

/**
 * Classifies an attempt from core-data, never from the editor store, so the
 * result is still right after `EditorProvider` unmounts (CMM-2008).
 *
 * @param {Object} attempt The attempt.
 * @param {Object} ref     The post reference captured when it started.
 * @return {Object} The outcome.
 */
function classify( attempt, { type, id } ) {
	if ( attempt.abort ) {
		return { outcome: 'aborted', reason: attempt.abort.reason };
	}
	if ( ! attempt.requestIssued ) {
		// An earlier `preSavePost` filter threw, or core refused silently.
		return { outcome: 'aborted', reason: 'pre_save_hook' };
	}

	const core = select( coreStore );
	const error = core.getLastEntitySaveError( 'postType', type, id );

	if ( error ) {
		const status = error?.data?.status;
		return {
			outcome: 'failed',
			ambiguous:
				AMBIGUOUS_CODES.includes( error.code ) ||
				AMBIGUOUS_STATUSES.includes( status ) ||
				! error.code,
			error: { code: error.code, message: error.message, status },
		};
	}

	const record = core.getEntityRecord( 'postType', type, id );
	return {
		outcome: 'saved',
		hookError: ! attempt.hooksSucceeded,
		post: {
			id: record?.id,
			status: record?.status,
			modifiedGmt: record?.modified_gmt,
			link: record?.link,
		},
	};
}

function finish( attempt, ref, result ) {
	const event = {
		attemptId: attempt?.attemptId ?? null,
		...result,
		core: coreView( ref ),
	};
	if ( result.outcome === 'saved' ) {
		s4.base = null;
		captureBase( ref );
	}
	journalSettle( event, ref );
	s4.attempts.push( event );
	log( 'onEditorSaveFinished', event );
	return event;
}

/**
 * What core itself reports, for comparison with the classification. Read
 * defensively: the editor store is empty after an unmount.
 *
 * @param {Object} ref The post reference.
 * @return {Object} Core's view.
 */
function coreView( { type, id } ) {
	const view = {};
	try {
		const editor = select( editorStore );
		view.succeeded = editor.didPostSaveRequestSucceed();
		view.failed = editor.didPostSaveRequestFail();
		view.editorPostId = editor.getCurrentPostId();
	} catch ( err ) {
		view.editorStoreError = err?.message;
	}
	view.dirty = select( coreStore ).hasEditsForEntityRecord(
		'postType',
		type,
		id
	);
	view.notices = select( noticesStore )
		.getNotices()
		.filter( ( notice ) => notice.id === 'editor-save' )
		.map( ( notice ) => `${ notice.status }: ${ notice.content }` );
	return view;
}

// ---------------------------------------------------------------------------
// Host journal stand-in (§4.4)
// ---------------------------------------------------------------------------

function journalRead() {
	try {
		return JSON.parse( window.localStorage.getItem( JOURNAL_KEY ) );
	} catch {
		return null;
	}
}

function journalWrite( pending ) {
	try {
		window.localStorage.setItem( JOURNAL_KEY, JSON.stringify( pending ) );
	} catch {}
	log( 'journal: pending', pending );
}

function journalClear( why ) {
	try {
		window.localStorage.removeItem( JOURNAL_KEY );
	} catch {}
	log( 'journal: cleared', { why } );
}

function journalSettle( event, ref ) {
	const pending = journalRead();
	if ( ! pending || pending.attemptId !== event.attemptId ) {
		return;
	}
	if ( event.outcome === 'saved' ) {
		// Rule 2: a match means the server holds the local draft.
		const current = hash( readSnapshot( ref ).content );
		journalClear(
			current === pending.snapshotHash
				? 'saved; local draft equals snapshot'
				: 'saved; newer local edits stay dirty'
		);
	} else if (
		( event.outcome === 'failed' && ! event.ambiguous ) ||
		event.outcome === 'aborted'
	) {
		journalClear( `definitive ${ event.outcome } (rule 3)` );
	} else {
		log( 'journal: kept pending (rule 4)', { outcome: event.outcome } );
	}
}

/**
 * Rule 4: decides a pending attempt from the server's copy, as the host
 * would on the next open.
 *
 * @return {Promise<Object>} The decision.
 */
export async function reconcile() {
	const pending = journalRead();
	if ( ! pending ) {
		log( 'reconcile: nothing pending' );
		return { pending: null };
	}
	const server = await apiFetch( {
		path: `${ getPostPath(
			pending.post
		) }?context=edit&_fields=modified_gmt,content`,
	} );
	const serverHash = hash( server.content.raw );
	const matches = serverHash === pending.snapshotHash;
	const afterStart =
		Date.parse( `${ server.modified_gmt }Z` ) >=
		Math.floor( Date.parse( pending.startedAt ) / 1000 ) * 1000;
	const decision = {
		attemptId: pending.attemptId,
		serverHash,
		snapshotHash: pending.snapshotHash,
		serverModifiedGmt: server.modified_gmt,
		startedAt: pending.startedAt,
		matches,
		afterStart,
		result: matches && afterStart ? 'saved' : 'dirty',
	};
	log( 'reconcile', decision );
	if ( decision.result === 'saved' ) {
		journalClear( 'reconciled as saved' );
	}
	return decision;
}

// ---------------------------------------------------------------------------
// Test actions
// ---------------------------------------------------------------------------

export function edit() {
	const text = `S4 edit at ${ clock() }`;
	dispatch( blockEditorStore ).insertBlocks(
		createBlock( 'core/paragraph', { content: text } )
	);
	log( 'edit', { text } );
}

export async function setMode( mode, { content = true } = {} ) {
	const query = new URLSearchParams( { mode } );
	if ( mode === 'conflict' ) {
		query.set( 'post', String( postRef().id ) );
		query.set( 'content', String( content ) );
	}
	const result = await apiFetch( {
		path: `${ MODE_PATH }?${ query }`,
		method: 'POST',
	} );
	s4.mode = result.mode;
	log( 'mode', result );
	return result;
}

export function crash() {
	s4.crashArmed = true;
	log( 'crash: armed' );
	s4.listeners.forEach( ( listener ) => listener() );
}

export function saveThenCrash( delayMs = 300 ) {
	const pending = save();
	setTimeout( crash, delayMs );
	return pending;
}

Object.assign( s4, {
	save,
	reconcile,
	edit,
	setMode,
	crash,
	saveThenCrash,
	hash,
	journalRead,
} );

function useTick() {
	const [ , setTick ] = useState( 0 );
	useEffect( () => {
		const listener = () => setTick( ( tick ) => tick + 1 );
		s4.listeners.add( listener );
		return () => s4.listeners.delete( listener );
	}, [] );
}

/**
 * Throws during render once armed, to trip the editor's error boundary.
 *
 * @return {null} Nothing.
 */
export function S4CrashTrigger() {
	useTick();
	if ( s4.crashArmed ) {
		throw new Error( 'S4 injected render error' );
	}
	return null;
}

const ACTIONS = [
	[ 'Edit', edit ],
	[ 'Save', () => save() ],
	[
		'Mode',
		() =>
			setMode( MODES[ ( MODES.indexOf( s4.mode ) + 1 ) % MODES.length ] ),
	],
	[ 'Conflict-mod', () => setMode( 'conflict', { content: false } ) ],
	[ 'Save+Crash', () => saveThenCrash() ],
	[ 'Reconcile', reconcile ],
	[
		'Clear',
		() => {
			s4.log.length = 0;
			log( 'cleared' );
		},
	],
];

/**
 * The spike's control panel, rendered outside the editor's error boundary.
 *
 * @return {Element} The panel.
 */
export function S4Panel() {
	useTick();
	const [ collapsed, setCollapsed ] = useState( false );

	useEffect( () => {
		apiFetch( { path: MODE_PATH } ).then(
			( result ) => {
				s4.mode = result.mode;
				log( 'mode', result );
			},
			( err ) => log( 'mode read failed', { code: err?.code } )
		);
		const pending = journalRead();
		if ( pending ) {
			log( 'journal: found pending at load', pending );
		}
	}, [] );

	return (
		<div
			style={ {
				position: 'fixed',
				top: 130,
				right: 4,
				zIndex: 999999,
				width: collapsed ? 'auto' : '70vw',
				background: 'rgba(160,255,200,.94)',
				color: '#000',
				font: '10px/1.25 monospace',
				padding: 4,
				borderRadius: 4,
			} }
		>
			<div style={ { display: 'flex', flexWrap: 'wrap', gap: 4 } }>
				<button
					type="button"
					aria-label="S4 toggle"
					onClick={ () => setCollapsed( ! collapsed ) }
				>
					S4 { s4.mode }
				</button>
				{ ! collapsed &&
					ACTIONS.map( ( [ label, handler ] ) => (
						<button
							key={ label }
							type="button"
							aria-label={ `S4 ${ label }` }
							onClick={ () =>
								Promise.resolve( handler() ).catch( ( err ) =>
									log( `${ label } error`, {
										message: err?.message,
									} )
								)
							}
						>
							{ label }
						</button>
					) ) }
			</div>
			{ ! collapsed && (
				<pre
					style={ {
						margin: '4px 0 0',
						maxHeight: '45vh',
						overflow: 'auto',
						whiteSpace: 'pre-wrap',
						wordBreak: 'break-all',
					} }
				>
					{ s4.log
						.slice( -30 )
						.map(
							( { t, message, data } ) =>
								`${ t } ${ message }${
									data ? ' ' + JSON.stringify( data ) : ''
								}`
						)
						.join( '\n' ) }
				</pre>
			) }
		</div>
	);
}
