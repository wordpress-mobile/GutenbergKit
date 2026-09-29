/**
 * External dependencies
 */
import { describe, it, expect, vi } from 'vitest';

/**
 * Internal dependencies
 */
import {
	readNativeUploadReference,
	standInForNativeUpload,
} from './native-upload-reference';

const SESSION = '0f8fad5b-d9cb-469f-a165-70867728950e';

function media( overrides = {} ) {
	return {
		url: 'gbk-media-file:///Uploads/abc/IMG_0001.HEIC',
		type: 'image/heic',
		nativeUpload: {
			sessionId: SESSION,
			filename: 'IMG_0001.HEIC',
			size: 5_000_000,
			previewUrl: 'gbk-media-file:///Uploads/abc/.preview.jpg',
			...overrides,
		},
	};
}

describe( 'standInForNativeUpload', () => {
	it( 'is named and typed like the real file, and names its session', async () => {
		// A jsdom `Blob`, as a browser's `Response.blob()` returns: jsdom's `File`
		// can't read Node's native one.
		const fetchPreview = vi.fn( async () => ( {
			blob: async () => new Blob( [ 'jpeg bytes' ] ),
		} ) );

		const standIn = await standInForNativeUpload( media(), {
			fetchPreview,
		} );

		expect( standIn.name ).toBe( 'IMG_0001.HEIC' );
		expect( standIn.type ).toBe( 'image/heic' );
		expect( fetchPreview ).toHaveBeenCalledWith(
			'gbk-media-file:///Uploads/abc/.preview.jpg'
		);
		expect( await readNativeUploadReference( standIn ) ).toBe( SESSION );
		expect( ( await standIn.text() ).startsWith( 'jpeg bytes' ) ).toBe(
			true
		);
	} );

	it( 'still builds a stand-in when the preview fails to load', async () => {
		const standIn = await standInForNativeUpload( media(), {
			fetchPreview: () =>
				Promise.reject( new TypeError( 'Load failed' ) ),
		} );

		expect( await readNativeUploadReference( standIn ) ).toBe( SESSION );
	} );

	it( 'skips the preview when there is none', async () => {
		const fetchPreview = vi.fn();

		const standIn = await standInForNativeUpload(
			media( { previewUrl: undefined } ),
			{ fetchPreview }
		);

		expect( fetchPreview ).not.toHaveBeenCalled();
		expect( await readNativeUploadReference( standIn ) ).toBe( SESSION );
	} );

	it( "rejects a file over the site's limit with core's message", async () => {
		await expect(
			standInForNativeUpload( media(), {
				maxUploadFileSize: 1_000_000,
				fetchPreview: vi.fn(),
			} )
		).rejects.toMatchObject( {
			code: 'SIZE_ABOVE_LIMIT',
			message:
				'IMG_0001.HEIC: This file exceeds the maximum upload size for this site.',
		} );
	} );

	it( 'accepts a file at the limit, and any file when the site sets none', async () => {
		await expect(
			standInForNativeUpload( media(), {
				maxUploadFileSize: 5_000_000,
				fetchPreview: vi.fn( async () => new Response( 'x' ) ),
			} )
		).resolves.toBeInstanceOf( File );
		await expect(
			standInForNativeUpload( media( { size: 10 ** 12 } ), {
				fetchPreview: vi.fn( async () => new Response( 'x' ) ),
			} )
		).resolves.toBeInstanceOf( File );
	} );
} );
