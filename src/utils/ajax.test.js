import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { configureAjax, getAjaxUrl } from './ajax';
import * as bridge from './bridge';
import * as logger from './logger';

vi.mock( './bridge' );
vi.mock( './logger' );

describe( 'configureAjax', () => {
	let originalWindow;
	let mockJQueryAjaxPrefilter;

	beforeEach( () => {
		vi.clearAllMocks();

		// Store original window state
		originalWindow = {
			wp: global.window.wp,
			jQuery: global.window.jQuery,
		};

		// Reset window.wp
		global.window.wp = undefined;

		// Mock jQuery
		mockJQueryAjaxPrefilter = vi.fn();
		global.window.jQuery = {
			ajaxPrefilter: mockJQueryAjaxPrefilter,
		};
	} );

	afterEach( () => {
		// Restore original window state
		global.window.wp = originalWindow.wp;
		global.window.jQuery = originalWindow.jQuery;
	} );

	describe( 'URL configuration', () => {
		it( 'should configure the AJAX URL when siteURL is provided', () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: 'https://example.com',
				authHeader: null,
			} );

			configureAjax();

			expect( global.window.wp.ajax.settings.url ).toBe(
				'https://example.com/wp-admin/admin-ajax.php'
			);
			expect( logger.debug ).toHaveBeenCalledWith(
				'AJAX URL configured'
			);
		} );

		it( 'should strip trailing slash from siteURL', () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: 'https://example.com/',
				authHeader: null,
			} );

			configureAjax();

			expect( global.window.wp.ajax.settings.url ).toBe(
				'https://example.com/wp-admin/admin-ajax.php'
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
			expect( logger.warn ).toHaveBeenCalledWith(
				'Unable to configure AJAX auth without siteURL'
			);
			expect( global.window.wp.ajax.settings.url ).toBeUndefined();
		} );

		it( 'should handle undefined siteURL', () => {
			bridge.getGBKit.mockReturnValue( {
				authHeader: 'Bearer token',
			} );

			configureAjax();

			expect( logger.warn ).toHaveBeenCalledWith(
				'Unable to configure AJAX URL without siteURL'
			);
			expect( logger.warn ).toHaveBeenCalledWith(
				'Unable to configure AJAX auth without siteURL'
			);
			expect( global.window.wp.ajax.settings.url ).toBeUndefined();
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
		it( 'should register a jQuery ajaxPrefilter', () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: 'https://example.com',
				authHeader: 'Bearer test-token',
			} );

			configureAjax();

			expect( mockJQueryAjaxPrefilter ).toHaveBeenCalledWith(
				expect.any( Function )
			);
			expect( logger.debug ).toHaveBeenCalledWith(
				'AJAX auth configured'
			);
		} );

		it( 'should inject auth header for same-site requests', () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: 'https://example.com',
				authHeader: 'Bearer test-token',
			} );

			configureAjax();

			const prefilter = mockJQueryAjaxPrefilter.mock.calls[ 0 ][ 0 ];
			const options = {
				url: 'https://example.com/wp-admin/admin-ajax.php',
			};
			prefilter( options );

			const mockXhr = { setRequestHeader: vi.fn() };
			options.beforeSend( mockXhr );

			expect( mockXhr.setRequestHeader ).toHaveBeenCalledWith(
				'Authorization',
				'Bearer test-token'
			);
		} );

		it( 'should not inject auth header for cross-origin requests', () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: 'https://example.com',
				authHeader: 'Bearer test-token',
			} );

			configureAjax();

			const prefilter = mockJQueryAjaxPrefilter.mock.calls[ 0 ][ 0 ];
			const options = { url: 'https://evil.com/steal' };
			prefilter( options );

			expect( options.beforeSend ).toBeUndefined();
		} );

		it( 'should not inject auth header for lookalike subdomain prefixes', () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: 'https://example.com',
				authHeader: 'Bearer test-token',
			} );

			configureAjax();

			const prefilter = mockJQueryAjaxPrefilter.mock.calls[ 0 ][ 0 ];
			const options = { url: 'https://example.com.evil.com/steal' };
			prefilter( options );

			expect( options.beforeSend ).toBeUndefined();
		} );

		it( 'should preserve original beforeSend', () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: 'https://example.com',
				authHeader: 'Bearer test-token',
			} );

			configureAjax();

			const prefilter = mockJQueryAjaxPrefilter.mock.calls[ 0 ][ 0 ];
			const originalBeforeSend = vi.fn();
			const options = {
				url: 'https://example.com/wp-admin/admin-ajax.php',
				beforeSend: originalBeforeSend,
			};
			prefilter( options );

			const mockXhr = { setRequestHeader: vi.fn() };
			options.beforeSend( mockXhr );

			expect( mockXhr.setRequestHeader ).toHaveBeenCalledWith(
				'Authorization',
				'Bearer test-token'
			);
			expect( originalBeforeSend ).toHaveBeenCalledWith( mockXhr );
		} );

		it( 'should pass the context, settings, and result through to the original beforeSend', () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: 'https://example.com',
				authHeader: 'Bearer test-token',
			} );

			configureAjax();

			const prefilter = mockJQueryAjaxPrefilter.mock.calls[ 0 ][ 0 ];
			const originalBeforeSend = vi.fn( () => false );
			const options = {
				url: 'https://example.com/wp-admin/admin-ajax.php',
				beforeSend: originalBeforeSend,
			};
			prefilter( options );

			const context = {};
			const mockXhr = { setRequestHeader: vi.fn() };
			const result = options.beforeSend.call( context, mockXhr, options );

			expect( originalBeforeSend ).toHaveBeenCalledWith(
				mockXhr,
				options
			);
			expect( originalBeforeSend.mock.contexts[ 0 ] ).toBe( context );
			// jQuery cancels the request when beforeSend returns false.
			expect( result ).toBe( false );
		} );

		it( 'should not inject auth header when a later prefilter moves the URL off the site', () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: 'https://example.com',
				authHeader: 'Bearer test-token',
			} );

			configureAjax();

			const prefilter = mockJQueryAjaxPrefilter.mock.calls[ 0 ][ 0 ];
			const options = {
				url: 'https://example.com/wp-admin/admin-ajax.php',
			};
			prefilter( options );
			// jQuery passes the same options object to every prefilter.
			options.url = 'https://proxy.example.net/wp-admin/admin-ajax.php';

			const mockXhr = { setRequestHeader: vi.fn() };
			options.beforeSend( mockXhr, options );

			expect( mockXhr.setRequestHeader ).not.toHaveBeenCalled();
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
			expect( mockJQueryAjaxPrefilter ).not.toHaveBeenCalled();
		} );

		it( 'should handle undefined authHeader', () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: 'https://example.com',
			} );

			configureAjax();

			expect( logger.warn ).toHaveBeenCalledWith(
				'Unable to configure AJAX auth without authHeader'
			);
			expect( mockJQueryAjaxPrefilter ).not.toHaveBeenCalled();
		} );
	} );

	describe( 'Integration tests', () => {
		it( 'should configure both URL and auth when both are provided', () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: 'https://example.com',
				authHeader: 'Bearer full-token',
			} );

			configureAjax();

			// Check URL configuration
			expect( global.window.wp.ajax.settings.url ).toBe(
				'https://example.com/wp-admin/admin-ajax.php'
			);

			// Check auth configuration
			expect( mockJQueryAjaxPrefilter ).toHaveBeenCalledWith(
				expect.any( Function )
			);

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
				'Unable to configure AJAX auth without siteURL'
			);
		} );
	} );

	describe( 'Edge cases', () => {
		it( 'should warn when jQuery is missing', () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: 'https://example.com',
				authHeader: 'Bearer no-jquery',
			} );

			delete global.window.jQuery;

			expect( () => configureAjax() ).not.toThrow();
			expect( logger.debug ).toHaveBeenCalledWith(
				'AJAX URL configured'
			);
			expect( logger.warn ).toHaveBeenCalledWith(
				'Unable to configure AJAX auth: jQuery not available'
			);
			expect( logger.debug ).not.toHaveBeenCalledWith(
				'AJAX auth configured'
			);
		} );

		it( 'should warn when jQuery is undefined', () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: 'https://example.com',
				authHeader: 'Bearer undefined-jquery',
			} );

			global.window.jQuery = undefined;

			expect( () => configureAjax() ).not.toThrow();
			expect( logger.debug ).toHaveBeenCalledWith(
				'AJAX URL configured'
			);
			expect( logger.warn ).toHaveBeenCalledWith(
				'Unable to configure AJAX auth: jQuery not available'
			);
			expect( logger.debug ).not.toHaveBeenCalledWith(
				'AJAX auth configured'
			);
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

		it( 'should not modify options when URL is missing', () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: 'https://example.com',
				authHeader: 'Bearer test-token',
			} );

			configureAjax();

			const prefilter = mockJQueryAjaxPrefilter.mock.calls[ 0 ][ 0 ];
			const options = {};
			prefilter( options );

			expect( options.beforeSend ).toBeUndefined();
		} );
	} );

	describe( 'Media AJAX configuration', () => {
		it( 'should alias wp.media.ajax to wp.ajax.send', () => {
			const mockSend = vi.fn();
			bridge.getGBKit.mockReturnValue( {
				siteURL: 'https://example.com',
				authHeader: null,
			} );

			global.window.wp = {
				ajax: {
					send: mockSend,
					post: vi.fn(),
					settings: {},
				},
			};

			configureAjax();

			expect( global.window.wp.media.ajax ).toBe( mockSend );
		} );

		it( 'should alias wp.media.post to wp.ajax.post', () => {
			const mockPost = vi.fn();
			bridge.getGBKit.mockReturnValue( {
				siteURL: 'https://example.com',
				authHeader: null,
			} );

			global.window.wp = {
				ajax: {
					send: vi.fn(),
					post: mockPost,
					settings: {},
				},
			};

			configureAjax();

			expect( global.window.wp.media.post ).toBe( mockPost );
		} );

		it( 'should not initialize wp.media when wp.ajax.send is unavailable', () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: 'https://example.com',
				authHeader: null,
			} );

			global.window.wp = {};

			configureAjax();

			expect( global.window.wp.media ).toBeUndefined();
			expect( logger.warn ).toHaveBeenCalledWith(
				'Unable to configure media AJAX: wp.ajax.send/post not available'
			);
		} );

		it( 'should warn when wp.ajax.send or wp.ajax.post are not available', () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: 'https://example.com',
				authHeader: null,
			} );

			// wp.ajax exists but without send/post (e.g., wp-util.js failed to load)
			global.window.wp = {
				ajax: {
					settings: {},
				},
			};

			configureAjax();

			expect( logger.warn ).toHaveBeenCalledWith(
				'Unable to configure media AJAX: wp.ajax.send/post not available'
			);
			expect( global.window.wp.media ).toBeUndefined();
		} );
	} );

	describe( 'Invalid siteURL handling', () => {
		it( 'should warn when siteURL is not a valid URL for auth config', () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: 'not-a-url',
				authHeader: 'Bearer test-token',
			} );

			configureAjax();

			expect( logger.warn ).toHaveBeenCalledWith(
				'Unable to configure AJAX auth: invalid siteURL'
			);
			expect( mockJQueryAjaxPrefilter ).not.toHaveBeenCalled();
		} );
	} );
} );

describe( 'getAjaxUrl', () => {
	it.each( [ 'https://example.com', 'https://example.com/' ] )(
		'builds the admin-ajax URL from %s',
		( siteURL ) => {
			expect( getAjaxUrl( siteURL ) ).toBe(
				'https://example.com/wp-admin/admin-ajax.php'
			);
		}
	);

	it.each( [ undefined, null, '' ] )(
		'returns undefined without a site URL (%s)',
		( siteURL ) => {
			expect( getAjaxUrl( siteURL ) ).toBeUndefined();
		}
	);
} );
