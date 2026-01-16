/**
 * External dependencies
 */
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';

/**
 * Internal dependencies
 */
import { requestLatestContent } from './bridge';

describe( 'requestLatestContent', () => {
	let originalWindow;

	beforeEach( () => {
		// Store original window properties
		originalWindow = {
			webkit: window.webkit,
			editorDelegate: window.editorDelegate,
		};
		// Clear any existing bridge properties
		delete window.webkit;
		delete window.editorDelegate;
	} );

	afterEach( () => {
		// Restore original window properties
		if ( originalWindow.webkit !== undefined ) {
			window.webkit = originalWindow.webkit;
		}
		if ( originalWindow.editorDelegate !== undefined ) {
			window.editorDelegate = originalWindow.editorDelegate;
		}
	} );

	describe( 'iOS bridge', () => {
		it( 'should return parsed response from iOS handler', async () => {
			const mockContent = {
				title: 'Test Title',
				content: 'Test Content',
			};
			window.webkit = {
				messageHandlers: {
					requestLatestContent: {
						postMessage: vi.fn().mockResolvedValue( mockContent ),
					},
				},
			};

			const result = await requestLatestContent();

			expect( result ).toEqual( mockContent );
			expect(
				window.webkit.messageHandlers.requestLatestContent.postMessage
			).toHaveBeenCalledWith( {} );
		} );

		it( 'should return null when iOS handler rejects', async () => {
			window.webkit = {
				messageHandlers: {
					requestLatestContent: {
						postMessage: vi
							.fn()
							.mockRejectedValue( new Error( 'Handler error' ) ),
					},
				},
			};

			const result = await requestLatestContent();

			expect( result ).toBeNull();
		} );

		it( 'should return null when iOS handler returns null', async () => {
			window.webkit = {
				messageHandlers: {
					requestLatestContent: {
						postMessage: vi.fn().mockResolvedValue( null ),
					},
				},
			};

			const result = await requestLatestContent();

			expect( result ).toBeNull();
		} );
	} );

	describe( 'Android bridge', () => {
		it( 'should return parsed JSON from Android interface', async () => {
			const mockContent = {
				title: 'Test Title',
				content: 'Test Content',
			};
			window.editorDelegate = {
				requestLatestContent: vi
					.fn()
					.mockReturnValue( JSON.stringify( mockContent ) ),
			};

			const result = await requestLatestContent();

			expect( result ).toEqual( mockContent );
			expect(
				window.editorDelegate.requestLatestContent
			).toHaveBeenCalled();
		} );

		it( 'should return null when Android returns null', async () => {
			window.editorDelegate = {
				requestLatestContent: vi.fn().mockReturnValue( null ),
			};

			const result = await requestLatestContent();

			expect( result ).toBeNull();
		} );

		it( 'should return null when Android returns empty string', async () => {
			window.editorDelegate = {
				requestLatestContent: vi.fn().mockReturnValue( '' ),
			};

			const result = await requestLatestContent();

			expect( result ).toBeNull();
		} );

		it( 'should return null when Android returns malformed JSON', async () => {
			window.editorDelegate = {
				requestLatestContent: vi
					.fn()
					.mockReturnValue( 'not valid json' ),
			};

			const result = await requestLatestContent();

			expect( result ).toBeNull();
		} );

		it( 'should return null when Android method throws', async () => {
			window.editorDelegate = {
				requestLatestContent: vi.fn().mockImplementation( () => {
					throw new Error( 'Method error' );
				} ),
			};

			const result = await requestLatestContent();

			expect( result ).toBeNull();
		} );
	} );

	describe( 'no bridge available', () => {
		it( 'should return null when no bridge is available', async () => {
			// Neither window.webkit nor window.editorDelegate is set

			const result = await requestLatestContent();

			expect( result ).toBeNull();
		} );

		it( 'should return null when webkit exists but handler does not', async () => {
			window.webkit = {
				messageHandlers: {},
			};

			const result = await requestLatestContent();

			expect( result ).toBeNull();
		} );

		it( 'should return null when editorDelegate exists but method does not', async () => {
			window.editorDelegate = {};

			const result = await requestLatestContent();

			expect( result ).toBeNull();
		} );
	} );

	describe( 'priority', () => {
		it( 'should prefer iOS bridge when both are available', async () => {
			const iosContent = {
				title: 'iOS Title',
				content: 'iOS Content',
			};
			const androidContent = {
				title: 'Android Title',
				content: 'Android Content',
			};

			window.webkit = {
				messageHandlers: {
					requestLatestContent: {
						postMessage: vi.fn().mockResolvedValue( iosContent ),
					},
				},
			};
			window.editorDelegate = {
				requestLatestContent: vi
					.fn()
					.mockReturnValue( JSON.stringify( androidContent ) ),
			};

			const result = await requestLatestContent();

			expect( result ).toEqual( iosContent );
			expect(
				window.editorDelegate.requestLatestContent
			).not.toHaveBeenCalled();
		} );
	} );
} );
