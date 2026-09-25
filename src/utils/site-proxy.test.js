/**
 * External dependencies
 */
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';

/**
 * Internal dependencies
 */
import { toSiteProxyUrl } from './site-proxy';

describe( 'toSiteProxyUrl', () => {
	afterEach( () => {
		vi.unstubAllEnvs();
	} );

	it( 'leaves URLs unchanged without the dev server proxy', () => {
		expect( toSiteProxyUrl( 'https://example.com/wp-json/' ) ).toBe(
			'https://example.com/wp-json/'
		);
	} );

	describe( 'with the dev server proxy', () => {
		const { origin } = window.location;

		beforeEach( () => {
			vi.stubEnv( 'GBK_SITE_PROXY_PATH', '/__site-proxy' );
		} );

		it( 'routes a cross-origin site URL through the proxy', () => {
			expect( toSiteProxyUrl( 'https://example.com/wp-json/?a=1' ) ).toBe(
				`${ origin }/__site-proxy/https/example.com/wp-json/?a=1`
			);
		} );

		it( 'keeps a non-default port', () => {
			expect( toSiteProxyUrl( 'http://10.0.2.2:8888/wp-json/' ) ).toBe(
				`${ origin }/__site-proxy/http/10.0.2.2:8888/wp-json/`
			);
		} );

		it.each( [
			[ 'a same-origin URL', `${ origin }/wp-json/` ],
			[ 'a relative URL', '/wp-json/' ],
			[ 'a non-HTTP URL', 'blob:https://example.com/123' ],
			[ 'an empty URL', '' ],
		] )( 'leaves %s unchanged', ( _label, url ) => {
			expect( toSiteProxyUrl( url ) ).toBe( url );
		} );
	} );
} );
