/**
 * External dependencies
 */
import { describe, it, expect, beforeEach, vi } from 'vitest';

/**
 * Internal dependencies
 */
import { createRelayFetch } from './fetch-relay';

vi.mock( './logger', () => ( {
	debug: vi.fn(),
	info: vi.fn(),
	warn: vi.fn(),
	error: vi.fn(),
} ) );

const RELAY_ROOT = 'http://127.0.0.1:5555/proxy/';
const NETWORK_PROXY = {
	port: 5555,
	token: 'relay-token',
	baseURL: RELAY_ROOT,
};

describe( 'createRelayFetch', () => {
	let next;

	beforeEach( () => {
		next = vi.fn( () => Promise.resolve( 'response' ) );
	} );

	/**
	 * The wrapper under test, over the shared `next` spy.
	 *
	 * @param {string} siteApiRoot The site's REST API root.
	 * @return {typeof fetch} The wrapped fetch.
	 */
	function relayFetch( siteApiRoot = 'https://example.com/wp-json/' ) {
		return createRelayFetch( next, {
			networkProxy: NETWORK_PROXY,
			siteApiRoot,
		} );
	}

	/** The URL `next` was called with. */
	function calledURL() {
		return next.mock.calls[ 0 ][ 0 ];
	}

	describe( 'requests it relays', () => {
		it( 'rewrites a site API request onto the relay route', async () => {
			await relayFetch()( 'https://example.com/wp-json/wp/v2/posts?x=1' );

			expect( calledURL() ).toBe( `${ RELAY_ROOT }wp/v2/posts?x=1` );
		} );

		it( 'swaps the site credential for the relay token', async () => {
			await relayFetch()( 'https://example.com/wp-json/wp/v2/posts', {
				headers: { Authorization: 'Bearer site-token' },
			} );

			const headers = new Headers( next.mock.calls[ 0 ][ 1 ].headers );
			expect( headers.get( 'Relay-Authorization' ) ).toBe(
				'Bearer relay-token'
			);
			expect( headers.get( 'Authorization' ) ).toBeNull();
		} );

		it( 'tolerates a host alias', async () => {
			// The same host under another spelling: `www.` versus bare.
			await relayFetch()(
				'https://www.example.com/wp-json/wp/v2/posts?page=2'
			);

			expect( calledURL() ).toBe( `${ RELAY_ROOT }wp/v2/posts?page=2` );
		} );

		it( 'tolerates a loopback host alias', async () => {
			// wp-env: the site is configured as `localhost`, and WordPress
			// writes `127.0.0.1` into the URLs it emits.
			await relayFetch( 'http://localhost:8888/wp-json/' )(
				'http://127.0.0.1:8888/wp-json/wp/v2/posts'
			);

			expect( calledURL() ).toBe( `${ RELAY_ROOT }wp/v2/posts` );
		} );

		it( 'tolerates a scheme and default port that differ from the root', async () => {
			await relayFetch()( 'http://example.com:80/wp-json/wp/v2/posts' );

			expect( calledURL() ).toBe( `${ RELAY_ROOT }wp/v2/posts` );
		} );

		it( 'accepts a root configured without a trailing slash', async () => {
			await relayFetch( 'https://example.com/wp-json' )(
				'https://example.com/wp-json/wp/v2/posts'
			);

			expect( calledURL() ).toBe( `${ RELAY_ROOT }wp/v2/posts` );
		} );

		it( 'merges into a root that already carries a query', async () => {
			// Plain permalinks: `https://site/?rest_route=/`.
			await relayFetch( 'https://example.com/?rest_route=/' )(
				'https://example.com/?rest_route=/wp/v2/posts&x=1'
			);

			expect( calledURL() ).toBe( `${ RELAY_ROOT }wp/v2/posts&x=1` );
		} );
	} );

	describe( 'requests it leaves alone', () => {
		/**
		 * Asserts the wrapper passed the call through untouched.
		 *
		 * @param {any} input The `fetch` input.
		 */
		async function expectPassthrough( input ) {
			await relayFetch()( input );
			expect( next ).toHaveBeenCalledWith( input, undefined );
		}

		it( 'a request to the relay server itself', async () => {
			// The upload route shares the relay's server and is addressed as
			// `localhost` rather than by address. Without matching the port,
			// the guard would come down to the path — which a root configured
			// as a bare `https://site/` would not distinguish.
			await expectPassthrough(
				'http://localhost:5555/upload?_embed=wp:featuredmedia'
			);
			await expectPassthrough(
				'http://127.0.0.1:5555/upload?_embed=wp:featuredmedia'
			);
			await expectPassthrough( `${ RELAY_ROOT }wp/v2/posts` );
		} );

		it( 'a no-cors request, whose response is opaque anyway', async () => {
			// The connectivity probe. Relayed, it would lose the bearer token
			// (a no-cors request carries only safelisted headers), take a 407,
			// and still resolve — reporting the site reachable because the
			// loopback server answered.
			const init = { method: 'HEAD', mode: 'no-cors' };
			await relayFetch()( 'https://example.com/wp-json/', init );

			expect( next ).toHaveBeenCalledWith(
				'https://example.com/wp-json/',
				init
			);
		} );

		it( 'a blob, data, or custom-scheme read', async () => {
			await expectPassthrough( 'blob:https://example.com/abc-123' );
			await expectPassthrough( 'data:text/plain,hello' );
			await expectPassthrough( 'gbk-media-file:///photo.jpg' );
		} );

		it( 'another origin entirely', async () => {
			await expectPassthrough(
				'https://public-api.wordpress.com/wpcom/v2/jetpack-ai-query'
			);
		} );

		it( 'another service on the site host', async () => {
			// A different port is a different server, however its paths are
			// shaped. Relaying it would answer one service's request with
			// another's response.
			await expectPassthrough(
				'https://example.com:8443/wp-json/wp/v2/posts'
			);
			await relayFetch( 'http://localhost:8888/wp-json/' )(
				'http://127.0.0.1:3000/wp-json/wp/v2/posts'
			);
			expect( next ).toHaveBeenCalledWith(
				'http://127.0.0.1:3000/wp-json/wp/v2/posts',
				undefined
			);
		} );

		it( 'a host alias the canonical form does not cover', async () => {
			// A documented limitation, not a decision: a site reached by LAN IP
			// emits `localhost` URLs, which are not recognized as the same host,
			// so paginated `Link` targets take the direct path — and fail under
			// Lockdown Mode. Provenance belongs at the relay, which knows the
			// response came from the configured site; see `relayUpstreamPath`.
			await relayFetch( 'http://192.168.1.50:8888/wp-json/' )(
				'http://localhost:8888/wp-json/wp/v2/posts?page=2'
			);

			expect( next ).toHaveBeenCalledWith(
				'http://localhost:8888/wp-json/wp/v2/posts?page=2',
				undefined
			);
		} );

		it( 'another WordPress site whose path matches the root', async () => {
			// A different host is a different server, however its paths are
			// shaped. Rewriting one onto the configured site would send its
			// request to the user's own site with the site credential.
			await expectPassthrough(
				'https://other-wp.example/wp-json/wp/v2/posts'
			);
		} );

		it( 'a sibling of the API root', async () => {
			// `https://site/wp-json` must not match `https://site/wp-jsonx/…`.
			await expectPassthrough( 'https://example.com/wp-jsonx/secrets' );
		} );

		it( 'a different site in a subdirectory multisite', async () => {
			// A path difference is a different site, not an alias. Matching
			// across them would route site B through site A's API root.
			await relayFetch( 'https://example.com/a/wp-json/' )(
				'https://example.com/b/wp-json/wp/v2/posts'
			);

			expect( calledURL() ).toBe(
				'https://example.com/b/wp-json/wp/v2/posts'
			);
		} );

		it( 'a Request object, which would have to be rebuilt', async () => {
			const request = new Request(
				'https://example.com/wp-json/wp/v2/posts'
			);
			await relayFetch()( request );

			expect( next ).toHaveBeenCalledWith( request, undefined );
		} );
	} );

	describe( 'failures', () => {
		it( 'rejects rather than throwing when a header is malformed', async () => {
			// api-fetch's middleware calls its `next` synchronously, so a throw
			// here would escape `apiFetch()` itself instead of reaching the
			// caller's `.catch()`.
			let pending;
			expect( () => {
				pending = relayFetch()(
					'https://example.com/wp-json/wp/v2/posts',
					{ headers: { 'Bad Header': 'value' } }
				);
			} ).not.toThrow();

			await expect( pending ).rejects.toThrow( TypeError );
			expect( next ).not.toHaveBeenCalled();
		} );
	} );
} );
