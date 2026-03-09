/**
 * Internal dependencies
 */
import { createNativeMediaUpload } from './native-upload';
import { getGBKit } from './bridge';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

vi.mock( './bridge', () => ( {
	getGBKit: vi.fn(),
} ) );

vi.mock( './logger', () => ( {
	error: vi.fn(),
	warn: vi.fn(),
	info: vi.fn(),
	debug: vi.fn(),
} ) );

// Mock WordPress data stores
const mockLockPostSaving = vi.fn();
const mockUnlockPostSaving = vi.fn();
const mockReceiveEntityRecords = vi.fn();

vi.mock( '@wordpress/data', () => ( {
	dispatch: vi.fn( ( store ) => {
		if ( store === 'core/editor' ) {
			return {
				lockPostSaving: mockLockPostSaving,
				unlockPostSaving: mockUnlockPostSaving,
			};
		}
		if ( store === 'core' ) {
			return {
				receiveEntityRecords: mockReceiveEntityRecords,
			};
		}
		return {};
	} ),
} ) );

vi.mock( '@wordpress/editor', () => ( {
	store: 'core/editor',
} ) );

vi.mock( '@wordpress/core-data', () => ( {
	store: 'core',
} ) );

describe( 'createNativeMediaUpload', () => {
	beforeEach( () => {
		vi.clearAllMocks();
	} );

	it( 'should return null when nativeUploadPort is not configured', () => {
		getGBKit.mockReturnValue( {} );

		expect( createNativeMediaUpload() ).toBeNull();
	} );

	it( 'should return a function when nativeUploadPort is configured', () => {
		getGBKit.mockReturnValue( {
			nativeUploadPort: 8080,
			nativeUploadToken: 'test-token',
		} );

		expect( typeof createNativeMediaUpload() ).toBe( 'function' );
	} );
} );

describe( 'nativeMediaUpload', () => {
	let mediaUpload;
	let onFileChange;
	let onError;

	beforeEach( () => {
		vi.clearAllMocks();

		getGBKit.mockReturnValue( {
			nativeUploadPort: 8080,
			nativeUploadToken: 'test-token',
		} );

		mediaUpload = createNativeMediaUpload();
		onFileChange = vi.fn();
		onError = vi.fn();

		// Mock URL.createObjectURL and revokeObjectURL
		global.URL.createObjectURL = vi.fn(
			( file ) => `blob:http://localhost/${ file.name }`
		);
		global.URL.revokeObjectURL = vi.fn();
	} );

	afterEach( () => {
		vi.restoreAllMocks();
	} );

	function createFile( name, type ) {
		return new File( [ 'content' ], name, { type } );
	}

	function createFileList( ...files ) {
		// FileList is not easily constructable; use an array with iterator
		const list = files;
		list[ Symbol.iterator ] = files[ Symbol.iterator ].bind( files );
		return list;
	}

	function mockFetchSuccess( mediaObject ) {
		global.fetch = vi.fn().mockResolvedValue( {
			ok: true,
			json: () => Promise.resolve( mediaObject ),
		} );
	}

	function mockFetchFailure( status, statusText, body = '' ) {
		global.fetch = vi.fn().mockResolvedValue( {
			ok: false,
			status,
			statusText,
			text: () => Promise.resolve( body ),
		} );
	}

	it( 'should create blob previews and call onFileChange immediately', () => {
		global.fetch = vi.fn( () => new Promise( () => {} ) ); // never resolves

		const file = createFile( 'photo.jpg', 'image/jpeg' );
		mediaUpload( {
			filesList: createFileList( file ),
			onFileChange,
			onError,
		} );

		expect( URL.createObjectURL ).toHaveBeenCalledWith( file );
		expect( onFileChange ).toHaveBeenCalledWith( [
			{
				url: 'blob:http://localhost/photo.jpg',
				mime: 'image/jpeg',
				type: 'image',
			},
		] );
	} );

	it( 'should lock post saving during upload', () => {
		global.fetch = vi.fn( () => new Promise( () => {} ) );

		const file = createFile( 'photo.jpg', 'image/jpeg' );
		mediaUpload( {
			filesList: createFileList( file ),
			onFileChange,
			onError,
		} );

		expect( mockLockPostSaving ).toHaveBeenCalledWith( 'native-upload' );
	} );

	it( 'should POST file to the native server with correct auth', () => {
		global.fetch = vi.fn( () => new Promise( () => {} ) );

		const file = createFile( 'photo.jpg', 'image/jpeg' );
		mediaUpload( {
			filesList: createFileList( file ),
			onFileChange,
			onError,
		} );

		expect( global.fetch ).toHaveBeenCalledWith(
			'http://localhost:8080/upload',
			expect.objectContaining( {
				method: 'POST',
				headers: { Authorization: 'Bearer test-token' },
			} )
		);

		const body = global.fetch.mock.calls[ 0 ][ 1 ].body;
		expect( body ).toBeInstanceOf( FormData );
		expect( body.get( 'file' ).name ).toBe( 'photo.jpg' );
	} );

	it( 'should deliver final media, revoke blobs, unlock saving, and update entity cache on success', async () => {
		const nativeResponse = {
			id: 123,
			url: 'https://example.com/photo.jpg',
			alt: '',
			caption: '',
			title: 'photo',
			mime: 'image/jpeg',
			type: 'image',
		};
		mockFetchSuccess( nativeResponse );

		const expectedWpMedia = {
			id: 123,
			source_url: 'https://example.com/photo.jpg',
			alt_text: '',
			caption: { raw: '', rendered: '' },
			title: { raw: 'photo', rendered: 'photo' },
			mime_type: 'image/jpeg',
			media_type: 'image',
			link: 'https://example.com/photo.jpg',
		};

		const file = createFile( 'photo.jpg', 'image/jpeg' );
		mediaUpload( {
			filesList: createFileList( file ),
			onFileChange,
			onError,
		} );

		// Wait for async operations
		await vi.waitFor( () => {
			expect( onFileChange ).toHaveBeenCalledTimes( 2 );
		} );

		// Second call delivers the final media in WP REST API shape
		expect( onFileChange ).toHaveBeenLastCalledWith( [ expectedWpMedia ] );

		// Blob URLs revoked
		expect( URL.revokeObjectURL ).toHaveBeenCalledWith(
			'blob:http://localhost/photo.jpg'
		);

		// Post saving unlocked
		expect( mockUnlockPostSaving ).toHaveBeenCalledWith( 'native-upload' );

		// Entity cache updated
		expect( mockReceiveEntityRecords ).toHaveBeenCalledWith(
			'root',
			'media',
			expectedWpMedia
		);
	} );

	it( 'should clean up blobs, unlock saving, and call onError on failure', async () => {
		mockFetchFailure( 500, 'Internal Server Error', 'Server crash' );

		const file = createFile( 'photo.jpg', 'image/jpeg' );
		mediaUpload( {
			filesList: createFileList( file ),
			onFileChange,
			onError,
		} );

		await vi.waitFor( () => {
			expect( onError ).toHaveBeenCalled();
		} );

		expect( onError ).toHaveBeenCalledWith(
			'Upload failed (500): Server crash'
		);

		expect( URL.revokeObjectURL ).toHaveBeenCalled();
		expect( mockUnlockPostSaving ).toHaveBeenCalledWith( 'native-upload' );
	} );

	it( 'should handle network errors', async () => {
		global.fetch = vi
			.fn()
			.mockRejectedValue( new Error( 'Network error' ) );

		const file = createFile( 'photo.jpg', 'image/jpeg' );
		mediaUpload( {
			filesList: createFileList( file ),
			onFileChange,
			onError,
		} );

		await vi.waitFor( () => {
			expect( onError ).toHaveBeenCalled();
		} );

		expect( onError ).toHaveBeenCalledWith( 'Network error' );
		expect( mockUnlockPostSaving ).toHaveBeenCalledWith( 'native-upload' );
	} );

	it( 'should filter files by allowedTypes', () => {
		global.fetch = vi.fn( () => new Promise( () => {} ) );

		const image = createFile( 'photo.jpg', 'image/jpeg' );
		const video = createFile( 'clip.mp4', 'video/mp4' );
		mediaUpload( {
			filesList: createFileList( image, video ),
			onFileChange,
			onError,
			allowedTypes: [ 'image' ],
		} );

		// Only the image should be uploaded
		expect( global.fetch ).toHaveBeenCalledTimes( 1 );
		expect( onFileChange ).toHaveBeenCalledWith( [
			expect.objectContaining( { mime: 'image/jpeg' } ),
		] );
	} );

	it( 'should do nothing when all files are filtered out', () => {
		global.fetch = vi.fn();

		const video = createFile( 'clip.mp4', 'video/mp4' );
		mediaUpload( {
			filesList: createFileList( video ),
			onFileChange,
			onError,
			allowedTypes: [ 'image' ],
		} );

		expect( global.fetch ).not.toHaveBeenCalled();
		expect( onFileChange ).not.toHaveBeenCalled();
		expect( mockLockPostSaving ).not.toHaveBeenCalled();
	} );

	it( 'should handle multiple files', async () => {
		let callCount = 0;
		global.fetch = vi.fn().mockImplementation( () => {
			callCount++;
			return Promise.resolve( {
				ok: true,
				json: () =>
					Promise.resolve( {
						id: callCount,
						url: `https://example.com/file${ callCount }.jpg`,
						alt: '',
						caption: '',
						title: `file${ callCount }`,
						mime: 'image/jpeg',
						type: 'image',
					} ),
			} );
		} );

		const file1 = createFile( 'a.jpg', 'image/jpeg' );
		const file2 = createFile( 'b.jpg', 'image/jpeg' );
		mediaUpload( {
			filesList: createFileList( file1, file2 ),
			onFileChange,
			onError,
		} );

		await vi.waitFor( () => {
			expect( onFileChange ).toHaveBeenCalledTimes( 2 );
		} );

		// Two fetch calls
		expect( global.fetch ).toHaveBeenCalledTimes( 2 );

		// Two blob URLs created and revoked
		expect( URL.createObjectURL ).toHaveBeenCalledTimes( 2 );
		expect( URL.revokeObjectURL ).toHaveBeenCalledTimes( 2 );

		// Two entity cache updates
		expect( mockReceiveEntityRecords ).toHaveBeenCalledTimes( 2 );
	} );

	it( 'should pass all file types when allowedTypes is empty', () => {
		global.fetch = vi.fn( () => new Promise( () => {} ) );

		const image = createFile( 'photo.jpg', 'image/jpeg' );
		const video = createFile( 'clip.mp4', 'video/mp4' );
		mediaUpload( {
			filesList: createFileList( image, video ),
			onFileChange,
			onError,
			allowedTypes: [],
		} );

		expect( global.fetch ).toHaveBeenCalledTimes( 2 );
	} );
} );
