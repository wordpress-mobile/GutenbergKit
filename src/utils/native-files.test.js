import { describe, it, expect, afterEach, vi } from 'vitest';
import { requestNativeFiles, withMimeType } from './native-files';

/**
 * Answers the next file input's click the way native code does: sets its files
 * and fires `change`, or fires `cancel` when there are none to give.
 *
 * @param {?File[]} files The files native code offers, or `null` to cancel.
 */
function answerFileInputWith( files ) {
	vi.spyOn( HTMLInputElement.prototype, 'click' ).mockImplementation(
		function () {
			if ( ! files ) {
				this.dispatchEvent( new Event( 'cancel' ) );
				return;
			}
			Object.defineProperty( this, 'files', { value: files } );
			this.dispatchEvent( new Event( 'change' ) );
		}
	);
}

describe( 'requestNativeFiles', () => {
	afterEach( () => {
		vi.restoreAllMocks();
		vi.useRealTimers();
	} );

	it( 'resolves with the files native code offers, in order', async () => {
		const video = new File( [ 'video' ], 'IMG_0001.MOV' );
		const photo = new File( [ 'photo' ], 'IMG_0002.HEIC' );
		answerFileInputWith( [ video, photo ] );

		expect( await requestNativeFiles() ).toEqual( [ video, photo ] );
	} );

	it( 'asks for several files with one hidden input, and removes it', async () => {
		let asked;
		vi.spyOn( HTMLInputElement.prototype, 'click' ).mockImplementation(
			function () {
				asked = {
					type: this.type,
					multiple: this.multiple,
					display: this.style.display,
					attached: document.body.contains( this ),
				};
				Object.defineProperty( this, 'files', {
					value: [ new File( [ 'x' ], 'a.jpg' ) ],
				} );
				this.dispatchEvent( new Event( 'change' ) );
			}
		);

		await requestNativeFiles();

		expect( asked ).toEqual( {
			type: 'file',
			multiple: true,
			display: 'none',
			attached: true,
		} );
		expect( document.querySelector( 'input[type="file"]' ) ).toBeNull();
	} );

	it( 'clicks before returning, while the caller still has user activation', async () => {
		vi.useFakeTimers();
		const click = vi
			.spyOn( HTMLInputElement.prototype, 'click' )
			.mockImplementation( () => {} );

		const request = requestNativeFiles( { timeout: 500 } );
		const rejection = expect( request ).rejects.toThrow();

		expect( click ).toHaveBeenCalledTimes( 1 );

		// Let the unanswered request time out, so its input doesn't outlive the test.
		await vi.advanceTimersByTimeAsync( 500 );
		await rejection;
	} );

	it( 'rejects when native code cancels the panel', async () => {
		answerFileInputWith( null );

		await expect( requestNativeFiles() ).rejects.toThrow(
			'Native code did not provide the files'
		);
	} );

	it( 'rejects when native code offers no files', async () => {
		answerFileInputWith( [] );

		await expect( requestNativeFiles() ).rejects.toThrow();
	} );

	it( 'rejects when native code never answers', async () => {
		vi.useFakeTimers();
		vi.spyOn( HTMLInputElement.prototype, 'click' ).mockImplementation(
			() => {}
		);

		const request = requestNativeFiles( { timeout: 500 } );
		const rejection = expect( request ).rejects.toThrow();
		await vi.advanceTimersByTimeAsync( 500 );

		await rejection;
		expect( document.querySelector( 'input[type="file"]' ) ).toBeNull();
	} );
} );

describe( 'withMimeType', () => {
	it( 'keeps a file whose type WebKit worked out', () => {
		const file = new File( [ 'x' ], 'a.mp4', { type: 'video/mp4' } );

		expect( withMimeType( file, 'video/quicktime' ) ).toBe( file );
	} );

	it( 'gives an untyped file the type native code reported', async () => {
		const file = new File( [ 'bytes' ], 'recording', { lastModified: 42 } );

		const typed = withMimeType( file, 'video/mp4' );

		expect( typed.type ).toBe( 'video/mp4' );
		expect( typed.name ).toBe( 'recording' );
		expect( typed.lastModified ).toBe( 42 );
		expect( await typed.text() ).toBe( 'bytes' );
	} );

	it( 'keeps an untyped file when native code reported no type', () => {
		const file = new File( [ 'x' ], 'recording' );

		expect( withMimeType( file, null ) ).toBe( file );
	} );
} );
