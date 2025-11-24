/**
 * External dependencies
 */
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';

/**
 * Internal dependencies
 */
import { initializeFetchInterceptor } from './fetch-interceptor';
import * as bridge from './bridge';

vi.mock( './bridge' );

describe( 'initializeFetchInterceptor', () => {
	let originalFetch;

	beforeEach( () => {
		// Reset window state
		delete window.__fetchInterceptorInitialized;

		// Store original fetch
		originalFetch = global.fetch;

		// Mock fetch to return a simple response
		global.fetch = vi.fn( () =>
			Promise.resolve( {
				ok: true,
				status: 200,
				headers: new Headers( {
					'content-type': 'application/json',
				} ),
				clone() {
					return {
						headers: this.headers,
						text: () => Promise.resolve( '{}' ),
						blob: () =>
							Promise.resolve(
								new Blob( [ '{}' ], {
									type: 'application/json',
								} )
							),
					};
				},
			} )
		);

		bridge.getGBKit.mockReturnValue( {
			enableNetworkLogging: true,
		} );
		bridge.onNetworkRequest = vi.fn();
	} );

	afterEach( () => {
		global.fetch = originalFetch;
		vi.clearAllMocks();
	} );

	it( 'should not initialize when network logging is disabled', () => {
		// Store the current fetch (which is the mock from beforeEach)
		const currentFetch = window.fetch;

		bridge.getGBKit.mockReturnValue( {
			enableNetworkLogging: false,
		} );

		initializeFetchInterceptor();

		// Should not have initialized
		expect( window.__fetchInterceptorInitialized ).toBeUndefined();
		// Fetch should not have been wrapped (should still be the same mock)
		expect( window.fetch ).toBe( currentFetch );
	} );

	describe( 'request body serialization', () => {
		it( 'should serialize FormData with files correctly', async () => {
			initializeFetchInterceptor();

			// Create a FormData with a file
			const formData = new FormData();
			const file = new File( [ 'test content' ], 'test.jpg', {
				type: 'image/jpeg',
			} );
			formData.append( 'file', file );
			formData.append( 'post', '123' );

			await window.fetch( 'https://example.com/upload', {
				method: 'POST',
				body: formData,
			} );

			// Wait for async logging to complete
			await new Promise( ( resolve ) => setTimeout( resolve, 10 ) );

			expect( bridge.onNetworkRequest ).toHaveBeenCalled();
			const loggedRequest = bridge.onNetworkRequest.mock.calls[ 0 ][ 0 ];

			expect( loggedRequest.requestBody ).toContain( '[FormData with' );
			expect( loggedRequest.requestBody ).toContain(
				'file=<File: test.jpg'
			);
			expect( loggedRequest.requestBody ).toContain( 'post=123' );
		} );

		it( 'should serialize Blob bodies correctly', async () => {
			initializeFetchInterceptor();

			const blob = new Blob( [ 'binary content' ], {
				type: 'image/png',
			} );

			await window.fetch( 'https://example.com/upload', {
				method: 'POST',
				body: blob,
			} );

			// Wait for async logging to complete
			await new Promise( ( resolve ) => setTimeout( resolve, 10 ) );

			expect( bridge.onNetworkRequest ).toHaveBeenCalled();
			const loggedRequest = bridge.onNetworkRequest.mock.calls[ 0 ][ 0 ];

			expect( loggedRequest.requestBody ).toMatch(
				/\[Blob: \d+ bytes, type: image\/png\]/
			);
		} );

		it( 'should serialize File bodies correctly', async () => {
			initializeFetchInterceptor();

			const file = new File( [ 'file content' ], 'document.pdf', {
				type: 'application/pdf',
			} );

			await window.fetch( 'https://example.com/upload', {
				method: 'POST',
				body: file,
			} );

			// Wait for async logging to complete
			await new Promise( ( resolve ) => setTimeout( resolve, 10 ) );

			expect( bridge.onNetworkRequest ).toHaveBeenCalled();
			const loggedRequest = bridge.onNetworkRequest.mock.calls[ 0 ][ 0 ];

			expect( loggedRequest.requestBody ).toMatch(
				/\[File: document\.pdf, \d+ bytes, type: application\/pdf\]/
			);
		} );

		it( 'should serialize ArrayBuffer bodies correctly', async () => {
			initializeFetchInterceptor();

			const buffer = new ArrayBuffer( 1024 );

			await window.fetch( 'https://example.com/upload', {
				method: 'POST',
				body: buffer,
			} );

			// Wait for async logging to complete
			await new Promise( ( resolve ) => setTimeout( resolve, 10 ) );

			expect( bridge.onNetworkRequest ).toHaveBeenCalled();
			const loggedRequest = bridge.onNetworkRequest.mock.calls[ 0 ][ 0 ];

			expect( loggedRequest.requestBody ).toBe(
				'[ArrayBuffer: 1024 bytes]'
			);
		} );

		it( 'should serialize URLSearchParams bodies correctly', async () => {
			initializeFetchInterceptor();

			const params = new URLSearchParams();
			params.append( 'key1', 'value1' );
			params.append( 'key2', 'value2' );

			await window.fetch( 'https://example.com/api', {
				method: 'POST',
				body: params,
			} );

			// Wait for async logging to complete
			await new Promise( ( resolve ) => setTimeout( resolve, 10 ) );

			expect( bridge.onNetworkRequest ).toHaveBeenCalled();
			const loggedRequest = bridge.onNetworkRequest.mock.calls[ 0 ][ 0 ];

			expect( loggedRequest.requestBody ).toBe(
				'key1=value1&key2=value2'
			);
		} );

		it( 'should handle string bodies correctly', async () => {
			initializeFetchInterceptor();

			const jsonString = JSON.stringify( { test: 'data' } );

			await window.fetch( 'https://example.com/api', {
				method: 'POST',
				body: jsonString,
			} );

			// Wait for async logging to complete
			await new Promise( ( resolve ) => setTimeout( resolve, 10 ) );

			expect( bridge.onNetworkRequest ).toHaveBeenCalled();
			const loggedRequest = bridge.onNetworkRequest.mock.calls[ 0 ][ 0 ];

			expect( loggedRequest.requestBody ).toBe( jsonString );
		} );

		it( 'should handle FormData with mixed content types', async () => {
			initializeFetchInterceptor();

			const formData = new FormData();
			formData.append( 'text', 'simple text value' );
			formData.append(
				'file1',
				new File( [ 'content1' ], 'image.png', { type: 'image/png' } )
			);
			formData.append(
				'file2',
				new File( [ 'content2' ], 'doc.pdf', {
					type: 'application/pdf',
				} )
			);
			formData.append(
				'blob',
				new Blob( [ 'blob data' ], {
					type: 'application/octet-stream',
				} )
			);

			await window.fetch( 'https://example.com/upload', {
				method: 'POST',
				body: formData,
			} );

			// Wait for async logging to complete
			await new Promise( ( resolve ) => setTimeout( resolve, 10 ) );

			expect( bridge.onNetworkRequest ).toHaveBeenCalled();
			const loggedRequest = bridge.onNetworkRequest.mock.calls[ 0 ][ 0 ];

			expect( loggedRequest.requestBody ).toContain(
				'[FormData with 4 field(s):'
			);
			expect( loggedRequest.requestBody ).toContain(
				'text=simple text value'
			);
			expect( loggedRequest.requestBody ).toContain(
				'file1=<File: image.png'
			);
			expect( loggedRequest.requestBody ).toContain(
				'file2=<File: doc.pdf'
			);
			// Note: Blob is converted to File by FormData with name "blob"
			expect( loggedRequest.requestBody ).toContain( 'blob=<File: blob' );
		} );

		it( 'should truncate long string values in FormData', async () => {
			initializeFetchInterceptor();

			const formData = new FormData();
			const longString = 'a'.repeat( 100 );
			formData.append( 'longField', longString );

			await window.fetch( 'https://example.com/api', {
				method: 'POST',
				body: formData,
			} );

			// Wait for async logging to complete
			await new Promise( ( resolve ) => setTimeout( resolve, 10 ) );

			expect( bridge.onNetworkRequest ).toHaveBeenCalled();
			const loggedRequest = bridge.onNetworkRequest.mock.calls[ 0 ][ 0 ];

			expect( loggedRequest.requestBody ).toContain( 'longField=' );
			expect( loggedRequest.requestBody ).toContain( '...' );
			expect( loggedRequest.requestBody.length ).toBeLessThan(
				longString.length + 50
			);
		} );

		it( 'should handle ReadableStream bodies', async () => {
			initializeFetchInterceptor();

			const stream = new ReadableStream( {
				start( controller ) {
					controller.enqueue( new Uint8Array( [ 1, 2, 3 ] ) );
					controller.close();
				},
			} );

			await window.fetch( 'https://example.com/upload', {
				method: 'POST',
				body: stream,
			} );

			// Wait for async logging to complete
			await new Promise( ( resolve ) => setTimeout( resolve, 10 ) );

			expect( bridge.onNetworkRequest ).toHaveBeenCalled();
			const loggedRequest = bridge.onNetworkRequest.mock.calls[ 0 ][ 0 ];

			expect( loggedRequest.requestBody ).toBe(
				'[ReadableStream - cannot serialize without consuming]'
			);
		} );

		it( 'should handle missing body gracefully', async () => {
			initializeFetchInterceptor();

			await window.fetch( 'https://example.com/api' );

			// Wait for async logging to complete
			await new Promise( ( resolve ) => setTimeout( resolve, 10 ) );

			expect( bridge.onNetworkRequest ).toHaveBeenCalled();
			const loggedRequest = bridge.onNetworkRequest.mock.calls[ 0 ][ 0 ];

			expect( loggedRequest.requestBody ).toBeNull();
		} );
	} );
} );
