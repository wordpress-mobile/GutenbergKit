/**
 * Spike (CMM-2557): save a VideoPress rating change through core `savePost`.
 *
 * Throwaway code. Renders a panel of buttons (insert block, cycle rating,
 * save, autosave, preview) and logs saving-state transitions and the
 * requests they cause to the panel and `window.__s2`.
 */
import apiFetch from '@wordpress/api-fetch';
import { createBlock, getBlockType } from '@wordpress/blocks';
import { store as blockEditorStore } from '@wordpress/block-editor';
import { dispatch, select, subscribe, useSelect } from '@wordpress/data';
import { store as editorStore } from '@wordpress/editor';
import { useEffect, useState } from '@wordpress/element';
import { info } from './logger';

const MEDIA_ID = Number(
	new URLSearchParams( window.location.search ).get( 's2Media' ) || 2928
);
const RATINGS = [ 'G', 'PG-13', 'R-17' ];

const s2 = { log: [], listeners: new Set() };
window.__s2 = s2;

function log( message, data ) {
	const entry = {
		t: ( performance.now() / 1000 ).toFixed( 1 ),
		message,
		data,
	};
	s2.log.push( entry );
	info( `[s2] ${ message } ${ JSON.stringify( data ?? {} ) }` );
	s2.listeners.forEach( ( listener ) => listener() );
}

function isInteresting( { path = '', url = '', method = 'GET' } ) {
	const target = path || url;
	return (
		method !== 'GET' ||
		/videopress|videos\/|autosaves/.test( target ) ||
		/\/wp\/v2\/posts\/\d+/.test( target )
	);
}

apiFetch.use( async ( options, next ) => {
	if ( ! isInteresting( options ) ) {
		return next( options );
	}
	const method = options.method ?? 'GET';
	const target = ( options.path || options.url ).split( '?' )[ 0 ];
	const body =
		options.data && /videopress/.test( target ) ? options.data : undefined;
	log( `→ ${ method } ${ target }`, body );
	try {
		const response = await next( options );
		log( `← ${ method } ${ target } ok`, summarizeResponse( response ) );
		return response;
	} catch ( err ) {
		log( `← ${ method } ${ target } FAIL`, {
			code: err?.code,
			message: err?.message,
		} );
		throw err;
	}
} );

function summarizeResponse( response ) {
	if ( ! response || typeof response !== 'object' ) {
		return response;
	}
	if ( response instanceof Response ) {
		return { status: response.status };
	}
	const { data, message, status, id, modified_gmt: modifiedGmt } = response;
	return { data, message, status, id, modifiedGmt };
}

let previousState = null;
subscribe( () => {
	const editor = select( editorStore );
	if ( ! editor.getCurrentPostId() ) {
		return;
	}
	const state = {
		saving: editor.isSavingPost(),
		autosaving: editor.isAutosavingPost(),
		previewing: editor.isPreviewingPost(),
	};
	const key = JSON.stringify( state );
	if ( key !== previousState ) {
		previousState = key;
		log( 'saving state', state );
	}
}, editorStore );

function findVideoPressBlock( selectFn = select ) {
	const stack = [ ...selectFn( blockEditorStore ).getBlocks() ];
	while ( stack.length ) {
		const block = stack.shift();
		if (
			block.name === 'videopress/video' ||
			( block.name === 'core/video' && block.attributes.guid )
		) {
			return block;
		}
		stack.push( ...block.innerBlocks );
	}
	return null;
}

async function insertVideoPress() {
	const media = await apiFetch( {
		path: `/wp/v2/media/${ MEDIA_ID }?context=edit`,
	} );
	const guid =
		media.jetpack_videopress_guid ?? media.jetpack_videopress?.guid ?? null;
	log( 'media', {
		id: media.id,
		guid,
		videopressKeys: Object.keys( media ).filter( ( k ) =>
			/videopress/.test( k )
		),
		blockRegistered: !! getBlockType( 'videopress/video' ),
	} );
	if ( ! guid ) {
		return;
	}
	const block = createBlock( 'videopress/video', { id: media.id, guid } );
	dispatch( blockEditorStore ).insertBlocks( block );
	log( 'inserted', { clientId: block.clientId } );
}

function cycleRating() {
	const block = findVideoPressBlock();
	if ( ! block ) {
		log( 'no VideoPress block' );
		return;
	}
	const current = block.attributes.rating;
	const next = RATINGS[ ( RATINGS.indexOf( current ) + 1 ) % RATINGS.length ];
	dispatch( blockEditorStore ).updateBlockAttributes( block.clientId, {
		rating: next,
	} );
	log( 'rating', { from: current, to: next } );
}

function runSave( label, action ) {
	return async () => {
		const editor = select( editorStore );
		log( `${ label }: start`, {
			dirty: editor.isEditedPostDirty(),
			autosaveable: editor.isEditedPostAutosaveable(),
			status: editor.getEditedPostAttribute( 'status' ),
		} );
		try {
			const result = await action();
			log( `${ label }: done`, {
				result: typeof result === 'string' ? result : undefined,
				dirty: editor.isEditedPostDirty(),
				succeeded: editor.didPostSaveRequestSucceed(),
				failed: editor.didPostSaveRequestFail(),
			} );
		} catch ( err ) {
			log( `${ label }: threw`, { message: err?.message } );
		}
	};
}

const ACTIONS = [
	[ 'Insert VP', insertVideoPress ],
	[ 'Rating', cycleRating ],
	[ 'Save', runSave( 'save', () => dispatch( editorStore ).savePost() ) ],
	[
		'Autosave',
		runSave( 'autosave', () => dispatch( editorStore ).autosave() ),
	],
	[
		'Preview',
		runSave( 'preview', () =>
			dispatch( editorStore ).__unstableSaveForPreview()
		),
	],
	[
		'Clear',
		() => {
			s2.log.length = 0;
			log( 'cleared' );
		},
	],
];

/**
 * The spike's control panel.
 *
 * @return {Element} The panel.
 */
export function S2Panel() {
	const [ , setTick ] = useState( 0 );
	const [ collapsed, setCollapsed ] = useState( false );
	const rating = useSelect(
		( s ) => findVideoPressBlock( s )?.attributes.rating ?? '-',
		[]
	);
	const postId = useSelect(
		( s ) => s( editorStore ).getCurrentPostId(),
		[]
	);

	useEffect( () => {
		const listener = () => setTick( ( tick ) => tick + 1 );
		s2.listeners.add( listener );
		return () => s2.listeners.delete( listener );
	}, [] );

	return (
		<div
			style={ {
				position: 'fixed',
				top: 130,
				right: 4,
				zIndex: 999999,
				width: collapsed ? 'auto' : '62vw',
				background: 'rgba(255,255,0,.92)',
				color: '#000',
				font: '10px/1.25 monospace',
				padding: 4,
				borderRadius: 4,
			} }
		>
			<div style={ { display: 'flex', flexWrap: 'wrap', gap: 4 } }>
				<button
					type="button"
					aria-label="S2 toggle"
					onClick={ () => setCollapsed( ! collapsed ) }
				>
					S2
				</button>
				{ ! collapsed &&
					ACTIONS.map( ( [ label, handler ] ) => (
						<button
							key={ label }
							type="button"
							aria-label={ `S2 ${ label }` }
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
					{ `post ${ postId } · rating ${ rating }\n` +
						s2.log
							.slice( -40 )
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
