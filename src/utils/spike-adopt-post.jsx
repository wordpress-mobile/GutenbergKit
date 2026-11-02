/**
 * Spike (CMM-2558): adopt a server post ID in place, with instrumentation.
 *
 * Throwaway code. Exposes `window.editor.adoptPost( id )`,
 * `window.editor.spikeCreateAndAdopt()` (simulates the host's create with the
 * current title and content), and `window.__spike` (counters and a log).
 */
import { createHigherOrderComponent } from '@wordpress/compose';
import { dispatch, select } from '@wordpress/data';
import { store as coreStore } from '@wordpress/core-data';
import { store as editorStore } from '@wordpress/editor';
import { store as blockEditorStore } from '@wordpress/block-editor';
import { useEffect } from '@wordpress/element';
import { addFilter } from '@wordpress/hooks';
import apiFetch from '@wordpress/api-fetch';
import { getPostPath } from './bridge';

const spike = {
	blockEditRenders: 0,
	blockEditMounts: 0,
	blockEditUnmounts: 0,
	contentChanged: 0,
	historyChanged: [],
	domBlocksAdded: 0,
	domBlocksRemoved: 0,
	adoptions: [],
	log: [],
};

window.__spike = spike;
window.editor = window.editor || {};

let currentPost = null;
let setLayoutPost = null;

function log( message, data ) {
	const entry = { t: Math.round( performance.now() ), message, data };
	spike.log.push( entry );
	// eslint-disable-next-line no-console
	console.log( `[spike] ${ message }`, JSON.stringify( data ?? {} ) );
	renderOverlay();
}

/**
 * Registers the Layout's post state so adoption can switch it.
 *
 * @param {Object}   post    The current post.
 * @param {Function} setPost The state setter.
 */
export function registerLayoutPost( post, setPost ) {
	currentPost = post;
	setLayoutPost = setPost;
}

export function countContentChanged() {
	spike.contentChanged++;
	log( 'onEditorContentChanged', { count: spike.contentChanged } );
}

export function countHistoryChanged( hasUndo, hasRedo ) {
	spike.historyChanged.push( { hasUndo, hasRedo } );
	log( 'onEditorHistoryChanged', { hasUndo, hasRedo } );
}

addFilter(
	'editor.BlockEdit',
	'gutenberg-kit/spike-count-block-edit',
	createHigherOrderComponent(
		( BlockEdit ) =>
			function SpikeCountedBlockEdit( props ) {
				spike.blockEditRenders++;
				useEffect( () => {
					spike.blockEditMounts++;
					return () => {
						spike.blockEditUnmounts++;
					};
				}, [] );
				return <BlockEdit { ...props } />;
			},
		'withSpikeCount'
	)
);

const observer = new MutationObserver( ( mutations ) => {
	for ( const mutation of mutations ) {
		for ( const node of mutation.addedNodes ) {
			if ( node.nodeType === 1 && node.matches?.( '[data-block]' ) ) {
				spike.domBlocksAdded++;
			}
		}
		for ( const node of mutation.removedNodes ) {
			if ( node.nodeType === 1 && node.matches?.( '[data-block]' ) ) {
				spike.domBlocksRemoved++;
			}
		}
	}
} );
observer.observe( document.documentElement, {
	childList: true,
	subtree: true,
} );

/**
 * Captures what adoption must preserve.
 *
 * @return {Object} The snapshot.
 */
function snapshot() {
	const editor = select( editorStore );
	const blockEditor = select( blockEditorStore );
	const active = document.activeElement;
	const domSelection = window.getSelection();
	const block = active?.closest?.( '[data-block]' );

	return {
		postId: editor.getCurrentPostId(),
		title: editor.getEditedPostAttribute( 'title' ),
		content: editor.getEditedPostContent(),
		isDirty: editor.isEditedPostDirty(),
		isNew: editor.isEditedPostNew(),
		hasUndo: editor.hasEditorUndo(),
		hasRedo: editor.hasEditorRedo(),
		blockClientIds: blockEditor.getClientIdsWithDescendants(),
		selectionStart: blockEditor.getSelectionStart(),
		activeElement: active
			? {
					tag: active.tagName,
					contentEditable: active.isContentEditable,
					block: block?.dataset.block ?? null,
					ariaLabel: active.getAttribute( 'aria-label' ),
			  }
			: null,
		domSelection: domSelection?.anchorNode
			? {
					anchorText: domSelection.anchorNode.textContent?.slice(
						0,
						40
					),
					anchorOffset: domSelection.anchorOffset,
			  }
			: null,
		editorRoot: document.querySelector( '.gutenberg-kit-editor' ),
		titleNode: document.querySelector( '.editor-post-title' ),
		firstBlockNode: document.querySelector( '[data-block]' ),
	};
}

function counters() {
	return {
		blockEditRenders: spike.blockEditRenders,
		blockEditMounts: spike.blockEditMounts,
		blockEditUnmounts: spike.blockEditUnmounts,
		contentChanged: spike.contentChanged,
		domBlocksAdded: spike.domBlocksAdded,
		domBlocksRemoved: spike.domBlocksRemoved,
		historyChanged: spike.historyChanged.length,
	};
}

/**
 * Adopts a server post ID in place of the unsaved `-1` post.
 *
 * @param {number} id The server post ID.
 * @return {Promise<Object>} The before/after measurements.
 */
async function adoptPost( id ) {
	const oldPost = currentPost;
	const { type } = oldPost;
	const before = snapshot();
	const countersBefore = counters();
	log( 'adopt:start', { from: oldPost.id, to: id } );

	const record = await apiFetch( {
		path: `${ getPostPath( { ...oldPost, id } ) }?context=edit`,
	} );

	const core = dispatch( coreStore );
	core.receiveEntityRecords( 'postType', type, record );
	core.finishResolution( 'getEntityRecord', [ 'postType', type, id ] );

	// Carry the unsaved record's edits (blocks, selection, and any field edits)
	// over, so the block editor keeps the same block objects.
	const oldEdits = select( coreStore ).getEntityRecordEdits(
		'postType',
		type,
		oldPost.id
	);
	const edits = { ...oldEdits };
	const oldTitle = select( coreStore ).getEditedEntityRecord(
		'postType',
		type,
		oldPost.id
	).title;
	if ( oldTitle !== record.title.raw ) {
		edits.title = oldTitle;
	}
	// An unedited post has no blocks edit, so the new ID would re-parse its
	// content into new client IDs. `?spikeNoBlocksCopy` measures that.
	if ( ! edits.blocks && ! window.__spikeNoBlocksCopy ) {
		edits.blocks = select( blockEditorStore ).getBlocks();
	}
	core.editEntityRecord( 'postType', type, id, edits, {
		undoIgnore: true,
	} );

	const startedAt = performance.now();
	setLayoutPost( { ...oldPost, id, status: record.status } );

	// Let React commit and effects run before measuring.
	await new Promise( ( resolve ) =>
		requestAnimationFrame( () => setTimeout( resolve, 500 ) )
	);

	const after = snapshot();
	const countersAfter = counters();
	const result = {
		from: oldPost.id,
		to: id,
		ms: Math.round( performance.now() - startedAt ),
		copiedEditKeys: Object.keys( edits ),
		recordStatus: record.status,
		before: summarize( before ),
		after: summarize( after ),
		same: {
			editorRoot: before.editorRoot === after.editorRoot,
			titleNode: before.titleNode === after.titleNode,
			firstBlockNode: before.firstBlockNode === after.firstBlockNode,
			blockClientIds:
				JSON.stringify( before.blockClientIds ) ===
				JSON.stringify( after.blockClientIds ),
			title:
				JSON.stringify( before.title ) ===
				JSON.stringify( after.title ),
			content: before.content === after.content,
			activeElement:
				JSON.stringify( before.activeElement ) ===
				JSON.stringify( after.activeElement ),
			selectionStart:
				JSON.stringify( before.selectionStart ) ===
				JSON.stringify( after.selectionStart ),
		},
		delta: Object.fromEntries(
			Object.entries( countersAfter ).map( ( [ key, value ] ) => [
				key,
				value - countersBefore[ key ],
			] )
		),
	};
	spike.adoptions.push( result );
	log( 'adopt:done', result );
	return result;
}

function summarize( snap ) {
	const {
		editorRoot,
		titleNode,
		firstBlockNode,
		blockClientIds,
		content,
		...rest
	} = snap;
	return {
		...rest,
		blockCount: blockClientIds.length,
		contentLength: content.length,
	};
}

/**
 * Simulates the host's create with the current title and content, then
 * adopts the new ID.
 *
 * @param {Object} [options]
 * @param {number} [options.delay] Milliseconds to wait before creating.
 * @return {Promise<Object>} The adoption result.
 */
async function spikeCreateAndAdopt( { delay = 0 } = {} ) {
	if ( delay ) {
		log( 'create:armed', { delay } );
		await new Promise( ( resolve ) => setTimeout( resolve, delay ) );
	}
	const editor = select( editorStore );
	const title = editor.getEditedPostAttribute( 'title' );
	const content = editor.getEditedPostContent();
	const { restNamespace, restBase } = currentPost;
	const created = await apiFetch( {
		path: `/${ restNamespace }/${ restBase }`,
		method: 'POST',
		data: { title, content, status: 'draft' },
	} );
	log( 'create:done', { id: created.id } );
	return adoptPost( created.id );
}

window.editor.adoptPost = adoptPost;
window.editor.spikeCreateAndAdopt = spikeCreateAndAdopt;

// Device runs: `?spikeAdopt=<ms>` arms create-and-adopt after the first edit,
// so adoption lands while the user is typing.
const armDelay = Number(
	new URLSearchParams( window.location.search ).get( 'spikeAdopt' )
);
let armed = false;
export function maybeArmOnFirstEdit() {
	if ( armDelay > 0 && ! armed && currentPost?.id === -1 ) {
		armed = true;
		spikeCreateAndAdopt( { delay: armDelay } ).catch( ( err ) =>
			log( 'adopt:error', { message: err.message } )
		);
	}
}

let overlay = null;
function renderOverlay() {
	if ( ! armDelay ) {
		return;
	}
	if ( ! overlay ) {
		overlay = document.createElement( 'pre' );
		overlay.style.cssText =
			'position:fixed;bottom:0;right:0;z-index:999999;margin:0;padding:4px;font:10px/1.2 monospace;background:rgba(255,255,0,.85);color:#000;pointer-events:none;max-width:60vw;white-space:pre-wrap;';
		document.body.appendChild( overlay );
	}
	const last = spike.adoptions.at( -1 );
	overlay.textContent = JSON.stringify(
		{
			post: currentPost?.id,
			...counters(),
			adoption: last
				? {
						to: last.to,
						ms: last.ms,
						same: last.same,
						delta: last.delta,
						focusAfter: last.after.activeElement,
						undoBefore: last.before.hasUndo,
						undoAfter: last.after.hasUndo,
				  }
				: null,
		},
		null,
		1
	);
}
