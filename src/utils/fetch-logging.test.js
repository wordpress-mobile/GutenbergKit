/**
 * External dependencies
 */
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';

/**
 * Internal dependencies
 */
import { createLoggingFetchWrapper } from './fetch-logging';
import * as bridge from './bridge';

vi.mock( './bridge' );

// Helper to await the nested, non-blocking async logging that occurs within the
// wrapper.
const waitForAsyncLogging = () =>
	new Promise( ( resolve ) => setTimeout( resolve, 10 ) );

/**
 * Wraps the current `window.fetch` with the logging wrapper, standing in for
 * what `installFetchWrappers` does at runtime.
 *
 * @return {void}
 */
const installLogging = () => {
	window.fetch = createLoggingFetchWrapper()( window.fetch.bind( window ) );
};

describe( 'createLoggingFetchWrapper', () => {
	let originalFetch;

	beforeEach( () => {
		// Store original fetch
		originalFetch = global.fetch;

		// Mock fetch to return a simple response
		global.fetch = vi.fn( () =>
			Promise.resolve( {
				ok: true,
				status: 200,
				statusText: 'OK',
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

	it( 'should produce no wrapper when network logging is disabled', () => {
		bridge.getGBKit.mockReturnValue( {
			enableNetworkLogging: false,
		} );

		// `null` rather than a pass-through, so the chain leaves `fetch`
		// untouched instead of installing a layer that does nothing.
		expect( createLoggingFetchWrapper() ).toBeNull();
	} );

	it( 'should derive statusText from status code when empty (HTTP/2)', async () => {
		// Mock fetch with empty statusText (common with HTTP/2)
		global.fetch = vi.fn( () =>
			Promise.resolve( {
				ok: true,
				status: 201,
				statusText: '', // Empty, as with HTTP/2
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

		installLogging();

		await window.fetch( 'https://example.com/api', { method: 'POST' } );

		await waitForAsyncLogging();

		expect( bridge.onNetworkRequest ).toHaveBeenCalledWith(
			expect.objectContaining( {
				status: 201,
				statusText: 'Created', // Derived from status code
			} )
		);
	} );

	describe( 'request header capture', () => {
		it( 'should capture headers from plain object with string URL', async () => {
			installLogging();

			await window.fetch( 'https://example.com/api', {
				method: 'POST',
				headers: {
					'Content-Type': 'application/json',
					Authorization: 'Bearer test-token',
					'X-Custom-Header': 'custom-value',
				},
			} );

			await waitForAsyncLogging();

			expect( bridge.onNetworkRequest ).toHaveBeenCalledWith(
				expect.objectContaining( {
					requestHeaders: expect.objectContaining( {
						'Content-Type': 'application/json',
						Authorization: 'Bearer test-token',
						'X-Custom-Header': 'custom-value',
					} ),
					statusText: 'OK',
				} )
			);
		} );

		it( 'should capture headers from Request object', async () => {
			installLogging();

			const request = new Request( 'https://example.com/api', {
				method: 'GET',
				headers: {
					Accept: 'application/json',
					'X-Request-ID': '12345',
				},
			} );

			await window.fetch( request );

			await waitForAsyncLogging();

			expect( bridge.onNetworkRequest ).toHaveBeenCalledWith(
				expect.objectContaining( {
					requestHeaders: expect.objectContaining( {
						accept: 'application/json',
						'x-request-id': '12345',
					} ),
				} )
			);
		} );

		it( 'should merge Request headers with init override', async () => {
			installLogging();

			const request = new Request( 'https://example.com/api', {
				headers: {
					'Content-Type': 'application/json',
					'X-Original': 'original-value',
				},
			} );

			await window.fetch( request, {
				headers: {
					'Content-Type': 'application/xml', // Override
					'X-Additional': 'additional-value', // Additional
				},
			} );

			await waitForAsyncLogging();

			expect( bridge.onNetworkRequest ).toHaveBeenCalledWith(
				expect.objectContaining( {
					requestHeaders: expect.objectContaining( {
						'content-type': 'application/xml', // Overridden (lowercase)
						'x-original': 'original-value', // Preserved (lowercase)
						'x-additional': 'additional-value', // Added (lowercase)
					} ),
				} )
			);
		} );

		it( 'should handle empty headers', async () => {
			installLogging();

			await window.fetch( 'https://example.com/api' );

			await waitForAsyncLogging();

			expect( bridge.onNetworkRequest ).toHaveBeenCalledWith(
				expect.objectContaining( {
					requestHeaders: {},
				} )
			);
		} );

		it( 'should handle Headers instance', async () => {
			installLogging();

			const headers = new Headers();
			headers.append( 'Authorization', 'Bearer token123' );
			headers.append( 'Content-Type', 'application/json' );

			await window.fetch( 'https://example.com/api', {
				method: 'POST',
				headers,
			} );

			await waitForAsyncLogging();

			expect( bridge.onNetworkRequest ).toHaveBeenCalledWith(
				expect.objectContaining( {
					requestHeaders: expect.objectContaining( {
						authorization: 'Bearer token123',
						'content-type': 'application/json',
					} ),
				} )
			);
		} );
	} );

	describe( 'request body serialization', () => {
		it( 'should serialize FormData with files correctly', async () => {
			installLogging();

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

			await waitForAsyncLogging();

			expect( bridge.onNetworkRequest ).toHaveBeenCalledWith(
				expect.objectContaining( {
					requestBody: expect.stringContaining( '[FormData with' ),
				} )
			);
			expect( bridge.onNetworkRequest ).toHaveBeenCalledWith(
				expect.objectContaining( {
					requestBody: expect.stringContaining(
						'file=<File: test.jpg'
					),
				} )
			);
			expect( bridge.onNetworkRequest ).toHaveBeenCalledWith(
				expect.objectContaining( {
					requestBody: expect.stringContaining( 'post=123' ),
				} )
			);
		} );

		it( 'should serialize Blob bodies correctly', async () => {
			installLogging();

			const blob = new Blob( [ 'binary content' ], {
				type: 'image/png',
			} );

			await window.fetch( 'https://example.com/upload', {
				method: 'POST',
				body: blob,
			} );

			await waitForAsyncLogging();

			expect( bridge.onNetworkRequest ).toHaveBeenCalledWith(
				expect.objectContaining( {
					requestBody: expect.stringMatching(
						/\[Blob: \d+ bytes, type: image\/png\]/
					),
				} )
			);
		} );

		it( 'should serialize File bodies correctly', async () => {
			installLogging();

			const file = new File( [ 'file content' ], 'document.pdf', {
				type: 'application/pdf',
			} );

			await window.fetch( 'https://example.com/upload', {
				method: 'POST',
				body: file,
			} );

			await waitForAsyncLogging();

			expect( bridge.onNetworkRequest ).toHaveBeenCalledWith(
				expect.objectContaining( {
					requestBody: expect.stringMatching(
						/\[File: document\.pdf, \d+ bytes, type: application\/pdf\]/
					),
				} )
			);
		} );

		it( 'should serialize ArrayBuffer bodies correctly', async () => {
			installLogging();

			const buffer = new ArrayBuffer( 1024 );

			await window.fetch( 'https://example.com/upload', {
				method: 'POST',
				body: buffer,
			} );

			await waitForAsyncLogging();

			expect( bridge.onNetworkRequest ).toHaveBeenCalledWith(
				expect.objectContaining( {
					requestBody: '[ArrayBuffer: 1024 bytes]',
				} )
			);
		} );

		it( 'should serialize URLSearchParams bodies correctly', async () => {
			installLogging();

			const params = new URLSearchParams();
			params.append( 'key1', 'value1' );
			params.append( 'key2', 'value2' );

			await window.fetch( 'https://example.com/api', {
				method: 'POST',
				body: params,
			} );

			await waitForAsyncLogging();

			expect( bridge.onNetworkRequest ).toHaveBeenCalledWith(
				expect.objectContaining( {
					requestBody: 'key1=value1&key2=value2',
				} )
			);
		} );

		it( 'should handle string bodies correctly', async () => {
			installLogging();

			const jsonString = JSON.stringify( { test: 'data' } );

			await window.fetch( 'https://example.com/api', {
				method: 'POST',
				body: jsonString,
			} );

			await waitForAsyncLogging();

			expect( bridge.onNetworkRequest ).toHaveBeenCalledWith(
				expect.objectContaining( {
					requestBody: jsonString,
				} )
			);
		} );

		it( 'should handle FormData with mixed content types', async () => {
			installLogging();

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

			await waitForAsyncLogging();

			expect( bridge.onNetworkRequest ).toHaveBeenCalledWith(
				expect.objectContaining( {
					requestBody: expect.stringContaining(
						'[FormData with 4 field(s):'
					),
				} )
			);
			expect( bridge.onNetworkRequest ).toHaveBeenCalledWith(
				expect.objectContaining( {
					requestBody: expect.stringContaining(
						'text=simple text value'
					),
				} )
			);
			expect( bridge.onNetworkRequest ).toHaveBeenCalledWith(
				expect.objectContaining( {
					requestBody: expect.stringContaining(
						'file1=<File: image.png'
					),
				} )
			);
			expect( bridge.onNetworkRequest ).toHaveBeenCalledWith(
				expect.objectContaining( {
					requestBody: expect.stringContaining(
						'file2=<File: doc.pdf'
					),
				} )
			);
			// Note: Blob is converted to File by FormData with name "blob"
			expect( bridge.onNetworkRequest ).toHaveBeenCalledWith(
				expect.objectContaining( {
					requestBody: expect.stringContaining( 'blob=<File: blob' ),
				} )
			);
		} );

		it( 'should truncate long string values in FormData', async () => {
			installLogging();

			const formData = new FormData();
			const longString = 'a'.repeat( 100 );
			formData.append( 'longField', longString );

			await window.fetch( 'https://example.com/api', {
				method: 'POST',
				body: formData,
			} );

			await waitForAsyncLogging();

			expect( bridge.onNetworkRequest ).toHaveBeenCalledWith(
				expect.objectContaining( {
					requestBody: expect.stringContaining( 'longField=' ),
				} )
			);
			expect( bridge.onNetworkRequest ).toHaveBeenCalledWith(
				expect.objectContaining( {
					requestBody: expect.stringContaining( '...' ),
				} )
			);
			expect( bridge.onNetworkRequest ).toHaveBeenCalledWith(
				expect.objectContaining( {
					requestBody: expect.stringMatching(
						new RegExp( `.{1,${ longString.length + 50 }}` )
					),
				} )
			);
		} );

		it( 'should handle ReadableStream bodies', async () => {
			installLogging();

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

			await waitForAsyncLogging();

			expect( bridge.onNetworkRequest ).toHaveBeenCalledWith(
				expect.objectContaining( {
					requestBody:
						'[ReadableStream - cannot serialize without consuming]',
				} )
			);
		} );

		it( 'should handle missing body gracefully', async () => {
			installLogging();

			await window.fetch( 'https://example.com/api' );

			await waitForAsyncLogging();

			expect( bridge.onNetworkRequest ).toHaveBeenCalledWith(
				expect.objectContaining( {
					requestBody: null,
				} )
			);
		} );
	} );
} );
