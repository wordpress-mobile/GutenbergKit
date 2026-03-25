/**
 * External dependencies
 */
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';

/**
 * Internal dependencies
 */
import { configureAjax } from './ajax';
import * as bridge from './bridge';
import * as logger from './logger';

vi.mock( './bridge' );
vi.mock( './logger' );

describe( 'configureAjax', () => {
	let originalWindow;
	let mockJQueryAjaxSetup;
	let originalWpAjaxSend;
	let originalWpAjaxPost;

	beforeEach( () => {
		vi.clearAllMocks();

		// Store original window state
		originalWindow = {
			wp: global.window.wp,
			ajaxurl: global.window.ajaxurl,
			jQuery: global.window.jQuery,
		};

		// Reset window.wp
		global.window.wp = undefined;
		global.window.ajaxurl = undefined;

		// Mock jQuery
		mockJQueryAjaxSetup = vi.fn();
		global.window.jQuery = {
			ajaxSetup: mockJQueryAjaxSetup,
		};

		// Create mock functions for wp.ajax methods
		originalWpAjaxSend = vi.fn( ( options ) => {
			// Simulate calling beforeSend if it exists
			if ( options?.beforeSend ) {
				const mockXhr = { setRequestHeader: vi.fn() };
				options.beforeSend( mockXhr );
			}
			return Promise.resolve();
		} );

		originalWpAjaxPost = vi.fn( ( options ) => {
			// Simulate calling beforeSend if it exists
			if ( options?.beforeSend ) {
				const mockXhr = { setRequestHeader: vi.fn() };
				options.beforeSend( mockXhr );
			}
			return Promise.resolve();
		} );
	} );

	afterEach( () => {
		// Restore original window state
		global.window.wp = originalWindow.wp;
		global.window.ajaxurl = originalWindow.ajaxurl;
		global.window.jQuery = originalWindow.jQuery;
	} );

	describe( 'URL configuration', () => {
		it( 'should configure ajax URLs when siteURL is provided', () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: 'https://example.com',
				authHeader: null,
			} );

			configureAjax();

			expect( global.window.ajaxurl ).toBe(
				'https://example.com/wp-admin/admin-ajax.php'
			);
			expect( global.window.wp.ajax.settings.url ).toBe(
				'https://example.com/wp-admin/admin-ajax.php'
			);
			expect( logger.debug ).toHaveBeenCalledWith(
				'AJAX URL configured'
			);
		} );

		it( 'should log warning when siteURL is missing', () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: null,
				authHeader: 'Bearer token',
			} );

			configureAjax();

			expect( logger.warn ).toHaveBeenCalledWith(
				'Unable to configure AJAX URL without siteURL'
			);
			expect( global.window.ajaxurl ).toBeUndefined();
		} );

		it( 'should handle undefined siteURL', () => {
			bridge.getGBKit.mockReturnValue( {
				authHeader: 'Bearer token',
			} );

			configureAjax();

			expect( logger.warn ).toHaveBeenCalledWith(
				'Unable to configure AJAX URL without siteURL'
			);
			expect( global.window.ajaxurl ).toBeUndefined();
		} );

		it( 'should properly initialize window.wp.ajax hierarchy', () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: 'https://example.com',
				authHeader: null,
			} );

			// Ensure window.wp doesn't exist initially
			expect( global.window.wp ).toBeUndefined();

			configureAjax();

			expect( global.window.wp ).toBeDefined();
			expect( global.window.wp.ajax ).toBeDefined();
			expect( global.window.wp.ajax.settings ).toBeDefined();
		} );
	} );

	describe( 'Auth configuration', () => {
		beforeEach( () => {
			// Setup wp.ajax with original methods
			global.window.wp = {
				ajax: {
					send: originalWpAjaxSend,
					post: originalWpAjaxPost,
					settings: {},
				},
			};
		} );

		it( 'should configure jQuery ajax with auth header', () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: null,
				authHeader: 'Bearer test-token',
			} );

			configureAjax();

			expect( mockJQueryAjaxSetup ).toHaveBeenCalledWith( {
				headers: {
					Authorization: 'Bearer test-token',
				},
			} );
			expect( logger.debug ).toHaveBeenCalledWith(
				'AJAX auth configured'
			);
		} );

		it( 'should wrap wp.ajax.send with auth header', async () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: null,
				authHeader: 'Bearer send-token',
			} );

			configureAjax();

			// Call the wrapped send method
			const options = { data: 'test' };
			await global.window.wp.ajax.send( 'test_action', options );

			// Verify the original was called
			expect( originalWpAjaxSend ).toHaveBeenCalled();

			// Verify beforeSend was added
			const calledOptions = originalWpAjaxSend.mock.calls[ 0 ][ 1 ];
			expect( calledOptions.beforeSend ).toBeDefined();

			// Verify auth header is set
			const mockXhr = { setRequestHeader: vi.fn() };
			calledOptions.beforeSend( mockXhr );
			expect( mockXhr.setRequestHeader ).toHaveBeenCalledWith(
				'Authorization',
				'Bearer send-token'
			);
		} );

		it( 'should wrap wp.ajax.post with auth header', async () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: null,
				authHeader: 'Bearer post-token',
			} );

			configureAjax();

			// Call the wrapped post method
			const options = {};
			await global.window.wp.ajax.post( 'test_action', options );

			// Verify the original was called
			expect( originalWpAjaxPost ).toHaveBeenCalled();

			// Verify beforeSend was added
			const calledOptions = originalWpAjaxPost.mock.calls[ 0 ][ 1 ];
			expect( calledOptions.beforeSend ).toBeDefined();

			// Verify auth header is set
			const mockXhr = { setRequestHeader: vi.fn() };
			calledOptions.beforeSend( mockXhr );
			expect( mockXhr.setRequestHeader ).toHaveBeenCalledWith(
				'Authorization',
				'Bearer post-token'
			);
		} );

		it( 'should preserve original beforeSend in wp.ajax.send', async () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: null,
				authHeader: 'Bearer preserve-token',
			} );

			configureAjax();

			// Call with existing beforeSend
			const originalBeforeSend = vi.fn();
			const options = { beforeSend: originalBeforeSend };
			await global.window.wp.ajax.send( 'test_action', options );

			// Get the wrapped beforeSend
			const calledOptions = originalWpAjaxSend.mock.calls[ 0 ][ 1 ];
			const mockXhr = { setRequestHeader: vi.fn() };
			calledOptions.beforeSend( mockXhr );

			// Verify both auth header and original beforeSend were called
			expect( mockXhr.setRequestHeader ).toHaveBeenCalledWith(
				'Authorization',
				'Bearer preserve-token'
			);
			expect( originalBeforeSend ).toHaveBeenCalledWith( mockXhr );
		} );

		it( 'should preserve original beforeSend in wp.ajax.post', async () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: null,
				authHeader: 'Bearer preserve-post-token',
			} );

			configureAjax();

			// Call with existing beforeSend
			const originalBeforeSend = vi.fn();
			const options = { beforeSend: originalBeforeSend };
			await global.window.wp.ajax.post( 'test_action', options );

			// Get the wrapped beforeSend
			const calledOptions = originalWpAjaxPost.mock.calls[ 0 ][ 1 ];
			const mockXhr = { setRequestHeader: vi.fn() };
			calledOptions.beforeSend( mockXhr );

			// Verify both auth header and original beforeSend were called
			expect( mockXhr.setRequestHeader ).toHaveBeenCalledWith(
				'Authorization',
				'Bearer preserve-post-token'
			);
			expect( originalBeforeSend ).toHaveBeenCalledWith( mockXhr );
		} );

		it( 'should log warning when authHeader is missing', () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: 'https://example.com',
				authHeader: null,
			} );

			configureAjax();

			expect( logger.warn ).toHaveBeenCalledWith(
				'Unable to configure AJAX auth without authHeader'
			);
			expect( mockJQueryAjaxSetup ).not.toHaveBeenCalled();
		} );

		it( 'should handle undefined authHeader', () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: 'https://example.com',
			} );

			configureAjax();

			expect( logger.warn ).toHaveBeenCalledWith(
				'Unable to configure AJAX auth without authHeader'
			);
			expect( mockJQueryAjaxSetup ).not.toHaveBeenCalled();
		} );
	} );

	describe( 'Integration tests', () => {
		it( 'should configure both URL and auth when both are provided', () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: 'https://example.com',
				authHeader: 'Bearer full-token',
			} );

			// Setup wp.ajax with methods
			global.window.wp = {
				ajax: {
					send: originalWpAjaxSend,
					post: originalWpAjaxPost,
					settings: {},
				},
			};

			configureAjax();

			// Check URL configuration
			expect( global.window.ajaxurl ).toBe(
				'https://example.com/wp-admin/admin-ajax.php'
			);
			expect( global.window.wp.ajax.settings.url ).toBe(
				'https://example.com/wp-admin/admin-ajax.php'
			);

			// Check auth configuration
			expect( mockJQueryAjaxSetup ).toHaveBeenCalledWith( {
				headers: {
					Authorization: 'Bearer full-token',
				},
			} );

			// Check debug logs
			expect( logger.debug ).toHaveBeenCalledWith(
				'AJAX URL configured'
			);
			expect( logger.debug ).toHaveBeenCalledWith(
				'AJAX auth configured'
			);
		} );

		it( 'should handle empty configuration object', () => {
			bridge.getGBKit.mockReturnValue( {} );

			configureAjax();

			expect( logger.warn ).toHaveBeenCalledWith(
				'Unable to configure AJAX URL without siteURL'
			);
			expect( logger.warn ).toHaveBeenCalledWith(
				'Unable to configure AJAX auth without authHeader'
			);
		} );
	} );

	describe( 'Edge cases', () => {
		it( 'should handle missing jQuery gracefully', () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: 'https://example.com',
				authHeader: 'Bearer no-jquery',
			} );

			delete global.window.jQuery;

			expect( () => configureAjax() ).not.toThrow();
			expect( logger.debug ).toHaveBeenCalledWith(
				'AJAX URL configured'
			);
			expect( logger.debug ).toHaveBeenCalledWith(
				'AJAX auth configured'
			);
		} );

		it( 'should handle undefined jQuery', () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: 'https://example.com',
				authHeader: 'Bearer undefined-jquery',
			} );

			global.window.jQuery = undefined;

			expect( () => configureAjax() ).not.toThrow();
			expect( logger.debug ).toHaveBeenCalledWith(
				'AJAX URL configured'
			);
			expect( logger.debug ).toHaveBeenCalledWith(
				'AJAX auth configured'
			);
		} );

		it( 'should handle missing wp.ajax.send method', () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: 'https://example.com',
				authHeader: 'Bearer no-send',
			} );

			global.window.wp = {
				ajax: {
					post: originalWpAjaxPost,
					settings: {},
				},
			};

			expect( () => configureAjax() ).not.toThrow();

			// Should not wrap send (it doesn't exist)
			expect( global.window.wp.ajax.send ).toBeUndefined();

			// Should still wrap post
			expect( global.window.wp.ajax.post ).not.toBe( originalWpAjaxPost );
		} );

		it( 'should handle missing wp.ajax.post method', () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: 'https://example.com',
				authHeader: 'Bearer no-post',
			} );

			global.window.wp = {
				ajax: {
					send: originalWpAjaxSend,
					settings: {},
				},
			};

			expect( () => configureAjax() ).not.toThrow();

			// Should not wrap post (it doesn't exist)
			expect( global.window.wp.ajax.post ).toBeUndefined();

			// Should still wrap send
			expect( global.window.wp.ajax.send ).not.toBe( originalWpAjaxSend );
		} );

		it( 'should handle missing wp.ajax entirely', () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: 'https://example.com',
				authHeader: 'Bearer no-ajax',
			} );

			global.window.wp = {};

			expect( () => configureAjax() ).not.toThrow();

			// Should create ajax object
			expect( global.window.wp.ajax ).toBeDefined();
			expect( global.window.wp.ajax.settings ).toBeDefined();
		} );

		it( 'should work with window.wp already partially initialized', () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: 'https://example.com',
				authHeader: null,
			} );

			// Pre-existing wp object with other properties
			global.window.wp = {
				data: { someData: 'test' },
			};

			configureAjax();

			// Should preserve existing properties
			expect( global.window.wp.data ).toEqual( { someData: 'test' } );

			// Should add ajax properties
			expect( global.window.wp.ajax ).toBeDefined();
			expect( global.window.wp.ajax.settings.url ).toBe(
				'https://example.com/wp-admin/admin-ajax.php'
			);
		} );

		it( 'should work when wp.ajax is partially initialized', () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: 'https://example.com',
				authHeader: null,
			} );

			// Pre-existing wp.ajax object without settings
			global.window.wp = {
				ajax: {
					someMethod: vi.fn(),
				},
			};

			configureAjax();

			// Should preserve existing methods
			expect( global.window.wp.ajax.someMethod ).toBeDefined();

			// Should add settings
			expect( global.window.wp.ajax.settings ).toBeDefined();
			expect( global.window.wp.ajax.settings.url ).toBe(
				'https://example.com/wp-admin/admin-ajax.php'
			);
		} );
	} );

	describe( 'Media AJAX configuration', () => {
		it( 'should alias wp.media.ajax to the wrapped wp.ajax.send', () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: 'https://example.com',
				authHeader: 'Bearer media-token',
			} );

			global.window.wp = {
				ajax: {
					send: originalWpAjaxSend,
					post: originalWpAjaxPost,
					settings: {},
				},
			};

			configureAjax();

			expect( global.window.wp.media.ajax ).toBe(
				global.window.wp.ajax.send
			);
		} );

		it( 'should alias wp.media.post to the wrapped wp.ajax.post', () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: 'https://example.com',
				authHeader: 'Bearer media-token',
			} );

			global.window.wp = {
				ajax: {
					send: originalWpAjaxSend,
					post: originalWpAjaxPost,
					settings: {},
				},
			};

			configureAjax();

			expect( global.window.wp.media.post ).toBe(
				global.window.wp.ajax.post
			);
		} );

		it( 'should initialize wp.media if it does not exist', () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: 'https://example.com',
				authHeader: null,
			} );

			global.window.wp = {};

			configureAjax();

			expect( global.window.wp.media ).toBeDefined();
		} );
	} );
} );
