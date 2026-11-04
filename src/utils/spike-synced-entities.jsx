/**
 * Spike S6 (CMM-2560): what happens to edits of entities other than the post.
 *
 * Throwaway code. Logs every REST write the editor attempts (outermost
 * middleware, so writes the guard blocks are logged too), lists core-data's
 * dirty entities, and lets the guard be lifted at runtime so one build covers
 * both trunk (the host saves) and the S1 lift (core `savePost()` writes).
 * Everything is on `window.__s6` for Playwright, CDP or the WebKit inspector.
 */
/* eslint-disable jsdoc/require-param, react-refresh/only-export-components */
import apiFetch from '@wordpress/api-fetch';
import {
	createBlock,
	getBlockBindingsSources,
	parse,
	registerBlockBindingsSource,
} from '@wordpress/blocks';
import { store as blockEditorStore } from '@wordpress/block-editor';
import { store as coreStore } from '@wordpress/core-data';
import { dispatch, select, subscribe } from '@wordpress/data';
import {
	privateApis as editorPrivateApis,
	store as editorStore,
} from '@wordpress/editor';
import { useEffect, useState } from '@wordpress/element';
import { store as noticesStore } from '@wordpress/notices';
import { unlock } from '../lock-unlock';
import { info } from './logger';

const SAFE_METHODS = [ 'GET', 'HEAD', 'OPTIONS' ];

const s6 = {
	liftGuard: false,
	requests: [],
	dirtyHistory: [],
	listeners: new Set(),
	installed: false,
};
window.__s6 = s6;

function notify() {
	s6.listeners.forEach( ( listener ) => listener() );
}

function clock() {
	return new Date().toISOString().slice( 11, 23 );
}

/**
 * Registers the request log. Called after `configureApiFetch`, so it is the
 * outermost middleware and sees the original method and the guard's refusals.
 */
export function installS6() {
	if ( s6.installed ) {
		return;
	}
	s6.installed = true;
	apiFetch.use( ( options, next ) => {
		const method = ( options.method ?? 'GET' ).toUpperCase();
		const path = options.path ?? options.url;
		// The navigation fallback GET can create a menu on the server.
		const isWrite =
			! SAFE_METHODS.includes( method ) ||
			String( path ).includes( 'navigation-fallback' );
		if ( ! isWrite ) {
			return next( options );
		}
		const entry = {
			t: clock(),
			method,
			path,
			bodyKeys: Object.keys( options.data ?? {} ),
			outcome: 'pending',
		};
		s6.requests.push( entry );
		info( `[s6] ${ method } ${ path }` );
		notify();
		return next( options ).then(
			( response ) => {
				entry.outcome = 'ok';
				notify();
				return response;
			},
			( error ) => {
				entry.outcome = error?.code ?? error?.status ?? 'error';
				notify();
				throw error;
			}
		);
	} );

	// Record every change in the set of dirty entities.
	let previous = '';
	subscribe( () => {
		const current = JSON.stringify( dirty() );
		if ( current !== previous ) {
			previous = current;
			s6.dirtyHistory.push( {
				t: clock(),
				dirty: JSON.parse( current ),
			} );
			notify();
		}
	}, coreStore );
}

/** Dirty entity records, with the edited property names of each. */
export function dirty() {
	const { __experimentalGetDirtyEntityRecords, getEntityRecordEdits } =
		select( coreStore );
	return __experimentalGetDirtyEntityRecords().map(
		( { kind, name, key, title, property } ) => ( {
			kind,
			name,
			key,
			title,
			property,
			edits: Object.keys( getEntityRecordEdits( kind, name, key ) ?? {} ),
		} )
	);
}

/** Editor and bridge signals that tell a host whether there is unsaved work. */
function signals() {
	const editor = select( editorStore );
	return {
		isEditedPostDirty: editor.isEditedPostDirty(),
		hasNonPostEntityChanges: editor.hasNonPostEntityChanges(),
		isSavingNonPostEntityChanges: editor.isSavingNonPostEntityChanges(),
		hasUndo: select( coreStore ).hasUndo(),
		titleAndContent: window.editor?.getTitleAndContent?.(),
	};
}

/** Core `savePost()`, as an editor-driven save would call it. */
async function savePost() {
	await dispatch( editorStore ).savePost();
	return result();
}

/** Core-data's multi-entity save, as WP Admin's save panel calls it. */
async function saveDirty( { includePost = true } = {} ) {
	const { type, id } = select( editorStore ).getCurrentPost();
	// Like core-data's `useIsDirty`, split `root/site` into one record per
	// edited property; `saveDirtyEntities` saves the site by property.
	const siteProperties = Object.keys(
		select( coreStore ).getEntityRecordEdits( 'root', 'site' ) ?? {}
	);
	const records = [
		...select( coreStore )
			.__experimentalGetDirtyEntityRecords()
			.filter(
				( record ) =>
					! ( record.kind === 'root' && record.name === 'site' )
			),
		...siteProperties.map( ( property ) => ( {
			kind: 'root',
			name: 'site',
			property,
		} ) ),
	].filter(
		( record ) =>
			includePost ||
			! (
				record.kind === 'postType' &&
				record.name === type &&
				record.key === id
			)
	);
	const values = await unlock( dispatch( coreStore ) ).saveDirtyEntities( {
		dirtyEntityRecords: records,
	} );
	return {
		errors: ( values ?? [] )
			.filter( ( value ) => value instanceof Error )
			.map( ( error ) => error.message ),
		...result(),
	};
}

function result() {
	const editor = select( editorStore );
	return {
		didPostSaveRequestSucceed: editor.didPostSaveRequestSucceed(),
		didPostSaveRequestFail: editor.didPostSaveRequestFail(),
		dirty: dirty(),
		notices: notices(),
		requests: s6.requests.slice( -10 ),
	};
}

function notices() {
	return select( noticesStore )
		.getNotices()
		.map( ( { id, status, content } ) => ( { id, status, content } ) );
}

/** Inserts a block at the end of the post, or after the selected block. */
function insert( name, attributes = {}, innerBlocks = [] ) {
	const block = createBlock(
		name,
		attributes,
		innerBlocks.map( ( [ n, a ] ) => createBlock( n, a ) )
	);
	dispatch( blockEditorStore ).insertBlock( block );
	return block.clientId;
}

/** Inserts raw block markup, as the code editor or a paste would. */
function insertMarkup( markup ) {
	const blocks = parse( markup );
	dispatch( blockEditorStore ).insertBlocks( blocks );
	return blocks.map( ( block ) => block.clientId );
}

const ENTITY_BLOCKS = [
	'core/block',
	'core/pattern',
	'core/template-part',
	'core/navigation',
	'core/page-list',
	'core/site-title',
	'core/site-tagline',
	'core/site-logo',
	'core/post-content',
];

/** What the inserters offer, and the settings that gate entity editing. */
function inventory() {
	const blockEditor = unlock( select( blockEditorStore ) );
	const patterns = blockEditor.__experimentalGetAllowedPatterns() ?? [];
	return {
		registered: ENTITY_BLOCKS.filter( ( name ) =>
			select( 'core/blocks' ).getBlockType( name )
		),
		canInsertAtRoot: Object.fromEntries(
			ENTITY_BLOCKS.map( ( name ) => [
				name,
				blockEditor.canInsertBlockType( name ),
			] )
		),
		inserterSyncedPatterns: blockEditor
			.getInserterItems()
			.filter( ( item ) => item.name === 'core/block' )
			.map( ( item ) => ( { id: item.id, title: item.title } ) ),
		userPatterns: patterns
			.filter( ( pattern ) => pattern.type === 'user' )
			.map( ( { name, title, syncStatus, content } ) => ( {
				name,
				title,
				syncStatus,
				// What GBK's native inserter inserts: it parses `content`.
				nativeInserterBlocks: parse( content ).map(
					( block ) => block.name
				),
			} ) ),
		renderingMode: select( editorStore ).getRenderingMode(),
		hasOnNavigateToEntityRecord:
			!! blockEditor.getSettings().onNavigateToEntityRecord,
		canUpdateSite: select( coreStore ).canUser( 'update', {
			kind: 'root',
			name: 'site',
		} ),
	};
}

/** Editing modes of a block and its descendants, by name. */
function editingModes( clientId ) {
	const blockEditor = select( blockEditorStore );
	const walk = ( id ) => [
		{
			clientId: id,
			name: blockEditor.getBlockName( id ),
			mode: blockEditor.getBlockEditingMode( id ),
		},
		...blockEditor.getBlockOrder( id ).flatMap( walk ),
	];
	return walk( clientId );
}

/** Saves only the site settings edits, rethrowing so the stack is visible. */
async function saveSite() {
	const edits = Object.keys(
		select( coreStore ).getEntityRecordEdits( 'root', 'site' ) ?? {}
	);
	try {
		await dispatch( coreStore ).__experimentalSaveSpecifiedEntityEdits(
			'root',
			'site',
			undefined,
			edits,
			{ throwOnError: true }
		);
		return { edits, ok: true, dirty: dirty() };
	} catch ( error ) {
		return {
			edits,
			ok: false,
			message: error?.message,
			code: error?.code,
			stack: error?.stack?.split( '\n' ).slice( 0, 8 ),
		};
	}
}

/** Registers the bindings sources WP Admin's edit-post registers. */
function registerBindings() {
	const list = () => Object.keys( getBlockBindingsSources() ?? {} );
	const before = list();
	// WP Admin bootstraps the server's sources (name, label, context) first;
	// the client registration is refused without a label.
	[
		[
			'core/pattern-overrides',
			'Pattern Overrides',
			[ 'pattern/overrides' ],
		],
		[ 'core/post-meta', 'Post Meta', [ 'postId', 'postType' ] ],
		[ 'core/post-data', 'Post Data', [ 'postId', 'postType' ] ],
		[ 'core/term-data', 'Term Data', [ 'termId', 'taxonomy' ] ],
	].forEach( ( [ name, label, usesContext ] ) =>
		registerBlockBindingsSource( { name, label, usesContext } )
	);
	const bootstrapped = list();
	unlock( editorPrivateApis ).registerCoreBlockBindingsSources();
	return { before, bootstrapped, after: list() };
}

function setLiftGuard( value ) {
	s6.liftGuard = value;
	info( `[s6] write guard ${ value ? 'lifted' : 'on' }` );
	notify();
}

Object.assign( s6, {
	dirty,
	signals,
	savePost,
	saveDirty,
	result,
	notices,
	insert,
	insertMarkup,
	inventory,
	editingModes,
	saveSite,
	registerBindings,
	setLiftGuard,
	clearLog: () => {
		s6.requests.length = 0;
		s6.dirtyHistory.length = 0;
		notify();
	},
} );

/**
 * A small panel to drive the spike on devices without a debugger. Collapsed,
 * it is a pill in the top corner.
 */
export function S6Panel() {
	const [ , setTick ] = useState( 0 );
	const [ open, setOpen ] = useState( false );
	const [ last, setLast ] = useState( '' );

	useEffect( () => {
		installS6();
		const listener = () => setTick( ( tick ) => tick + 1 );
		s6.listeners.add( listener );
		return () => s6.listeners.delete( listener );
	}, [] );

	const run = ( label, fn ) => async () => {
		try {
			const value = await fn();
			setLast( `${ label }: ${ JSON.stringify( value?.dirty ?? '' ) }` );
		} catch ( error ) {
			setLast( `${ label } threw: ${ error?.message ?? error }` );
		}
	};

	const style = {
		position: 'fixed',
		top: 4,
		right: 4,
		zIndex: 100000,
		background: 'rgba(255,255,240,0.95)',
		border: '1px solid #999',
		font: '11px/1.3 monospace',
		padding: 4,
		maxWidth: open ? 330 : undefined,
		maxHeight: open ? '60vh' : undefined,
		overflow: 'auto',
	};

	if ( ! open ) {
		return (
			<button
				style={ style }
				onClick={ () => setOpen( true ) }
				data-s6="open"
			>
				S6 { s6.liftGuard ? 'lift' : 'guard' } · dirty{ ' ' }
				{ safeDirty().length }
			</button>
		);
	}

	return (
		<div style={ style } data-s6="panel">
			<div>
				<button onClick={ () => setOpen( false ) }>×</button>{ ' ' }
				<button
					data-s6="lift"
					onClick={ () => setLiftGuard( ! s6.liftGuard ) }
				>
					guard: { s6.liftGuard ? 'LIFTED' : 'on' }
				</button>{ ' ' }
				<button data-s6="save" onClick={ run( 'savePost', savePost ) }>
					savePost
				</button>{ ' ' }
				<button
					data-s6="save-dirty"
					onClick={ run( 'saveDirty', saveDirty ) }
				>
					saveDirty
				</button>
			</div>
			<div>
				<b>dirty</b>
				{ safeDirty().map( ( record ) => (
					<div
						key={ `${ record.kind }/${ record.name }/${ record.key }` }
					>
						{ record.kind }/{ record.name }/{ String( record.key ) }{ ' ' }
						[{ record.edits.join( ',' ) }]
					</div>
				) ) }
			</div>
			<div>
				<b>writes</b>
				{ s6.requests.slice( -8 ).map( ( request, index ) => (
					<div key={ index }>
						{ request.t } { request.method } { request.path } →{ ' ' }
						{ String( request.outcome ) }
					</div>
				) ) }
			</div>
			{ last && <div>{ last }</div> }
		</div>
	);
}

function safeDirty() {
	try {
		return dirty();
	} catch {
		return [];
	}
}
