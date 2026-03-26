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
	let mockJQueryAjaxPrefilter;

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
		mockJQueryAjaxPrefilter = vi.fn();
		global.window.jQuery = {
			ajaxPrefilter: mockJQueryAjaxPrefilter,
		};
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

		it( 'should strip trailing slash from siteURL', () => {
			bridge.getGBKit.mockReturnValue( {
				siteURL: 'https://example.com/',
				authHeader: null,
			} );

			configureAjax();

			expect( global.window.ajaxurl ).toBe(
				'https://example.com/wp-admin/admin-ajax.php'
			);
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
			expect( logger.warn ).toHaveBeenCalledWith(
				'Unable to configure AJAX auth without siteURL'
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
			expect( global.window.ajaxurl ).toBe(
				'https://example.com/wp-admin/admin-ajax.php'
			);
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
