/**
 * External dependencies
 */
import { describe, it, expect, afterEach } from 'vitest';

/**
 * Internal dependencies
 */
import { modalize, unmodalize } from '../aria-helper';

const ariaHidden = ( id ) =>
	document.getElementById( id ).getAttribute( 'aria-hidden' );

afterEach( () => {
	document.body.innerHTML = '';
} );

describe( 'modalize / unmodalize', () => {
	it( 'hides siblings outside the modal element and reveals them on unmodalize', () => {
		document.body.innerHTML = `
			<div id="root">editor</div>
			<div id="modal"><span id="modal-child">m</span></div>
		`;
		const handle = modalize( document.getElementById( 'modal' ) );

		expect( ariaHidden( 'root' ) ).toBe( 'true' );
		expect( ariaHidden( 'modal' ) ).toBe( null );

		unmodalize( handle );
		expect( ariaHidden( 'root' ) ).toBe( null );
	} );

	it( 'keeps shared siblings hidden until every overlapping modal is reversed', () => {
		// Both modals keep the same two containers reachable and therefore hide
		// the same siblings—the real call pattern once `useModalize` always
		// modalizes the clip and overlay containers.
		document.body.innerHTML = `
			<div id="root">editor</div>
			<div id="clip"></div>
			<div id="overlay"></div>
		`;
		const clip = document.getElementById( 'clip' );
		const overlay = document.getElementById( 'overlay' );

		const first = modalize( clip, overlay );
		const second = modalize( clip, overlay );

		// The second modal records #root even though the first already hid it.
		expect( ariaHidden( 'root' ) ).toBe( 'true' );
		expect( second.has( document.getElementById( 'root' ) ) ).toBe( true );

		// Closing the first modal while the second is open must NOT reveal #root.
		unmodalize( first );
		expect( ariaHidden( 'root' ) ).toBe( 'true' );

		// Closing the last modal reveals it.
		unmodalize( second );
		expect( ariaHidden( 'root' ) ).toBe( null );
	} );

	it( 'reverses batches by identity regardless of close order', () => {
		document.body.innerHTML = `
			<div id="root">editor</div>
			<div id="clip"></div>
			<div id="overlay"></div>
		`;
		const clip = document.getElementById( 'clip' );
		const overlay = document.getElementById( 'overlay' );

		const first = modalize( clip, overlay );
		const second = modalize( clip, overlay );

		// Close in the SAME order they opened (not reverse); still correct.
		unmodalize( first );
		expect( ariaHidden( 'root' ) ).toBe( 'true' );
		unmodalize( second );
		expect( ariaHidden( 'root' ) ).toBe( null );
	} );

	it( 'never reveals an element hidden by authored markup, not a batch', () => {
		document.body.innerHTML = `
			<div id="root" aria-hidden="true">pre-hidden</div>
			<div id="modal"><span id="modal-child">m</span></div>
		`;
		const handle = modalize( document.getElementById( 'modal' ) );

		// #root was already aria-hidden and no batch owns it, so it is left
		// alone and not recorded.
		expect( handle.has( document.getElementById( 'root' ) ) ).toBe( false );

		unmodalize( handle );
		// Its authored aria-hidden survives.
		expect( ariaHidden( 'root' ) ).toBe( 'true' );
	} );

	it( 'does not hide live regions or scripts', () => {
		document.body.innerHTML = `
			<div id="modal">m</div>
			<div id="status" role="status">status</div>
			<div id="live" aria-live="polite">live</div>
		`;
		const handle = modalize( document.getElementById( 'modal' ) );

		expect( ariaHidden( 'status' ) ).toBe( null );
		expect( ariaHidden( 'live' ) ).toBe( null );

		unmodalize( handle );
	} );

	it( 'ignores an unknown handle', () => {
		document.body.innerHTML = `<div id="root">editor</div><div id="modal">m</div>`;
		const handle = modalize( document.getElementById( 'modal' ) );

		unmodalize( new Set() ); // unknown handle: no-op
		expect( ariaHidden( 'root' ) ).toBe( 'true' );

		unmodalize( handle );
		expect( ariaHidden( 'root' ) ).toBe( null );
	} );
} );
