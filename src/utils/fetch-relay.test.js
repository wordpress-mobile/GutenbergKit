import { Blob as NodeBlob } from 'node:buffer';
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { createRelayFetch, createRelayFetchWrapper } from './fetch-relay';
import { getGBKit } from './bridge';
import { warn } from './logger';

vi.mock( './bridge', () => ( {
	getGBKit: vi.fn(),
} ) );

vi.mock( './logger', () => ( {
	debug: vi.fn(),
	info: vi.fn(),
	warn: vi.fn(),
	error: vi.fn(),
} ) );

const RELAY_ROOT = 'gbk-rest://relay/proxy/';
const FORWARD_URL = 'gbk-rest://relay/forward';
const REST_RELAY = { baseURL: RELAY_ROOT, forwardURL: FORWARD_URL };

/**
 * The relay URL a request for another host is sent to.
 *
 * @param {string} url The request's URL.
 * @return {string} The forward route's URL for it.
 */
function forwarded( url ) {
	return `${ FORWARD_URL }?url=${ encodeURIComponent( url ) }`;
}

describe( 'createRelayFetch', () => {
	let next;

	beforeEach( () => {
		next = vi.fn( () => Promise.resolve( 'response' ) );
	} );

	/**
	 * The wrapper under test, over the shared `next` spy.
	 *
	 * @param {string} siteApiRoot The site's REST API root.
	 * @param {Object} restRelay   Where the relay is.
	 * @return {typeof fetch} The wrapped fetch.
	 */
	function relayFetch(
		siteApiRoot = 'https://example.com/wp-json/',
		restRelay = REST_RELAY
	) {
		return createRelayFetch( next, { restRelay, siteApiRoot } );
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

		it( "keeps the caller's Authorization and sends no cookies", async () => {
			// Native code decides what reaches the site: it keeps a caller's
			// own token, and adds the site credential only when there is none.
			await relayFetch()( 'https://example.com/wp-json/wp/v2/posts', {
				headers: { Authorization: 'Bearer own-token', 'X-Other': '1' },
			} );

			const init = next.mock.calls[ 0 ][ 1 ];
			const headers = new Headers( init.headers );
			expect( headers.get( 'Authorization' ) ).toBe( 'Bearer own-token' );
			expect( headers.get( 'X-Other' ) ).toBe( '1' );
			expect( init.credentials ).toBe( 'omit' );
		} );

		describe( 'bodies', () => {
			// jsdom's `Blob` and Node's `Response` don't interoperate, so these
			// use Node's own `Blob`. A browser has one family of both.

			/** The init `next` was called with. */
			function calledInit() {
				return next.mock.calls[ 0 ][ 1 ];
			}

			it( 'sends a string body as it is', async () => {
				await relayFetch()( 'https://example.com/wp-json/wp/v2/posts', {
					method: 'POST',
					body: '{"title":"Hello"}',
				} );

				expect( calledInit().body ).toBe( '{"title":"Hello"}' );
			} );

			it( 'reads a Blob into an ArrayBuffer, which WebKit would otherwise drop', async () => {
				await relayFetch()(
					'https://example.com/wp-json/videopress/v1/upload-relay/abc',
					{
						method: 'POST',
						headers: {
							'Content-Type': 'application/offset+octet-stream',
						},
						body: new NodeBlob( [ 'chunk bytes' ] ),
					}
				);

				const { body, headers } = calledInit();
				expect( body ).toBeInstanceOf( ArrayBuffer );
				expect( new TextDecoder().decode( body ) ).toBe(
					'chunk bytes'
				);
				expect( new Headers( headers ).get( 'Content-Type' ) ).toBe(
					'application/offset+octet-stream'
				);
			} );

			it( 'serializes FormData, and takes the boundary from the serialization', async () => {
				// jsdom's `FormData` and Node's `Response` don't interoperate, so
				// the browser's serialization is stood in for.
				const serialized = new TextEncoder().encode(
					'--xyz multipart'
				);
				vi.stubGlobal(
					'Response',
					class {
						constructor( source ) {
							this.source = source;
							this.headers = new Headers( {
								'Content-Type':
									'multipart/form-data; boundary=xyz',
							} );
						}
						arrayBuffer() {
							return Promise.resolve( serialized.buffer );
						}
					}
				);
				const form = new FormData();
				form.append( 'title', 'Hello' );

				try {
					await relayFetch()(
						'https://example.com/wp-json/wp/v2/media',
						{
							method: 'POST',
							// A stale type, as a caller copying headers would send.
							headers: { 'Content-Type': 'multipart/form-data' },
							body: form,
						}
					);
				} finally {
					vi.unstubAllGlobals();
				}

				const { body, headers } = calledInit();
				expect( body ).toBe( serialized.buffer );
				expect( new Headers( headers ).get( 'Content-Type' ) ).toBe(
					'multipart/form-data; boundary=xyz'
				);
			} );

			it( 'gives a Blob without a Content-Type its own type', async () => {
				await relayFetch()( 'https://example.com/wp-json/wp/v2/posts', {
					method: 'POST',
					body: new NodeBlob( [ '{}' ], {
						type: 'application/json',
					} ),
				} );

				expect(
					new Headers( calledInit().headers ).get( 'Content-Type' )
				).toBe( 'application/json' );
			} );

			it( 'reads a Blob another window made, which is not an instance of this one', async () => {
				// Here Node's `Blob` is what an iframe's is in a browser: a
				// `Blob` that the global `Blob` does not recognize.
				const foreign = new NodeBlob( [ 'chunk bytes' ], {
					type: 'video/mp4',
				} );
				expect( foreign ).not.toBeInstanceOf( Blob );

				await relayFetch()( 'https://example.com/wp-json/wp/v2/posts', {
					method: 'POST',
					body: foreign,
				} );

				const { body, headers } = calledInit();
				expect( body ).toBeInstanceOf( ArrayBuffer );
				expect( new TextDecoder().decode( body ) ).toBe(
					'chunk bytes'
				);
				expect( new Headers( headers ).get( 'Content-Type' ) ).toBe(
					'video/mp4'
				);
			} );

			it( 'leaves a request without a body without one', async () => {
				await relayFetch()( 'https://example.com/wp-json/wp/v2/posts' );

				expect( calledInit().body ).toBeUndefined();
			} );
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

		describe( 'a root that carries its route in the query', () => {
			// Plain permalinks. WordPress advertises the root through
			// `add_query_arg`, which percent-encodes the route.
			const PLAIN_ROOT = 'https://example.com/index.php?rest_route=%2F';

			it( 'reads the route out of the query and carries the rest', async () => {
				await relayFetch( PLAIN_ROOT )(
					'https://example.com/index.php?rest_route=/wp/v2/posts&x=1'
				);

				expect( calledURL() ).toBe( `${ RELAY_ROOT }wp/v2/posts?x=1` );
			} );

			it( 'recognizes the route with its separators encoded', async () => {
				// The spelling every request actually arrives in: api-fetch's
				// locale middleware rebuilds the query through `addQueryArgs`,
				// and WordPress builds `Link` through `add_query_arg`, both of
				// which percent-encode the value.
				await relayFetch( PLAIN_ROOT )(
					'https://example.com/index.php?rest_route=%2Fwp%2Fv2%2Fposts&page=2&_locale=user'
				);

				expect( calledURL() ).toBe(
					`${ RELAY_ROOT }wp/v2/posts?page=2&_locale=user`
				);
			} );

			it( 'accepts a root whose route is spelled with a literal slash', async () => {
				await relayFetch( 'https://example.com/?rest_route=/' )(
					'https://example.com/?rest_route=%2Fwp%2Fv2%2Fposts'
				);

				expect( calledURL() ).toBe( `${ RELAY_ROOT }wp/v2/posts` );
			} );

			it( 'relays the root itself', async () => {
				await relayFetch( PLAIN_ROOT )(
					'https://example.com/index.php?rest_route=%2F'
				);

				expect( calledURL() ).toBe( RELAY_ROOT );
			} );

			it( 'continues a route that names a site', async () => {
				// A namespaced site's root carries more than `/` in the route,
				// and every request continues it.
				await relayFetch(
					'https://public-api.example/wp-json/?rest_route=/sites/1/'
				)(
					'https://public-api.example/wp-json/?rest_route=%2Fsites%2F1%2Fwp%2Fv2%2Fposts&_locale=user'
				);

				expect( calledURL() ).toBe(
					`${ RELAY_ROOT }wp/v2/posts?_locale=user`
				);
			} );

			it( 'forwards the same page without the route', async () => {
				const url = 'https://example.com/index.php?p=1';
				await relayFetch( PLAIN_ROOT )( url );

				expect( calledURL() ).toBe( forwarded( url ) );
			} );

			it( 'forwards a route outside the root', async () => {
				const url =
					'https://public-api.example/wp-json/?rest_route=%2Fsites%2F2%2Fwp%2Fv2%2Fposts';
				await relayFetch(
					'https://public-api.example/wp-json/?rest_route=/sites/1/'
				)( url );

				expect( calledURL() ).toBe( forwarded( url ) );
			} );
		} );
	} );

	describe( 'requests it leaves alone', () => {
		/**
		 * Asserts the wrapper passed the call through untouched.
		 *
		 * @param {unknown} input The `fetch` input.
		 */
		async function expectPassthrough( input ) {
			await relayFetch()( input );
			expect( next ).toHaveBeenCalledWith( input, undefined );
		}

		it( 'a request to native code itself', async () => {
			await expectPassthrough( 'gbk-upload://upload/sessions' );
			await expectPassthrough( `${ RELAY_ROOT }wp/v2/posts` );
		} );

		it( 'a no-cors request, whose response is opaque anyway', async () => {
			// The connectivity probe. Relayed, it would resolve whenever native
			// code answered, reporting the site reachable when it may not be.
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

		it( "a request to the page's own origin, which CORS doesn't apply to", async () => {
			// A dev server's, when the editor is loaded from one.
			await expectPassthrough(
				`${ window.location.origin }/src/translations.json`
			);
		} );

		it( 'another host, when native code offers no forward route', async () => {
			const url =
				'https://public-api.wordpress.com/wpcom/v2/jetpack-ai-query';
			await relayFetch( undefined, { baseURL: RELAY_ROOT } )( url );

			expect( next ).toHaveBeenCalledWith( url, undefined );
		} );

		it( 'a Request object, which would have to be rebuilt', async () => {
			const request = new Request(
				'https://example.com/wp-json/wp/v2/posts'
			);
			await relayFetch()( request );

			expect( next ).toHaveBeenCalledWith( request, undefined );
		} );
	} );

	describe( 'requests for other hosts', () => {
		it( 'forwards another origin entirely, with its own credential', async () => {
			// Jetpack AI signs its requests to WordPress.com with a token of its
			// own, which has to arrive as it was sent.
			const url =
				'https://public-api.wordpress.com/wpcom/v2/jetpack-ai-query?stream=true';
			await relayFetch()( url, {
				method: 'POST',
				headers: { Authorization: 'Bearer jwt' },
				body: '{"question":"Hi"}',
			} );

			expect( calledURL() ).toBe( forwarded( url ) );
			const init = next.mock.calls[ 0 ][ 1 ];
			expect( new Headers( init.headers ).get( 'Authorization' ) ).toBe(
				'Bearer jwt'
			);
			expect( init.method ).toBe( 'POST' );
			expect( init.body ).toBe( '{"question":"Hi"}' );
			expect( init.credentials ).toBe( 'omit' );
		} );

		it( 'forwards another service on the site host', async () => {
			// A different port is a different server, however its paths are
			// shaped. Relaying it onto the API root would answer one service's
			// request with another's response.
			const url = 'https://example.com:8443/wp-json/wp/v2/posts';
			await relayFetch()( url );

			expect( calledURL() ).toBe( forwarded( url ) );
		} );

		it( 'forwards a host alias the canonical form does not cover', async () => {
			// A documented limitation, not a decision: a site reached by LAN IP
			// emits `localhost` URLs, which are not recognized as the same host,
			// so paginated `Link` targets go out without the site credential.
			// Provenance belongs at the relay, which knows the response came
			// from the configured site; see `relayUpstreamPath`.
			const url = 'http://localhost:8888/wp-json/wp/v2/posts?page=2';
			await relayFetch( 'http://192.168.1.50:8888/wp-json/' )( url );

			expect( calledURL() ).toBe( forwarded( url ) );
		} );

		it( 'forwards another WordPress site whose path matches the root', async () => {
			// A different host is a different server, however its paths are
			// shaped. Rewriting one onto the configured site would send its
			// request to the user's own site with the site credential.
			const url = 'https://other-wp.example/wp-json/wp/v2/posts';
			await relayFetch()( url );

			expect( calledURL() ).toBe( forwarded( url ) );
		} );

		it( 'forwards a sibling of the API root', async () => {
			// `https://site/wp-json` must not match `https://site/wp-jsonx/…`.
			const url = 'https://example.com/wp-jsonx/secrets';
			await relayFetch()( url );

			expect( calledURL() ).toBe( forwarded( url ) );
		} );

		it( 'forwards a different site in a subdirectory multisite', async () => {
			// A path difference is a different site, not an alias. Matching
			// across them would route site B through site A's API root.
			const url = 'https://example.com/b/wp-json/wp/v2/posts';
			await relayFetch( 'https://example.com/a/wp-json/' )( url );

			expect( calledURL() ).toBe( forwarded( url ) );
		} );

		it( 'forwards the whole URL, query and all', async () => {
			const url = 'https://example.org/api?q=a%20b&tags=x,y';
			await relayFetch()( url );

			const relayed = new URL( calledURL() );
			expect( relayed.searchParams.get( 'url' ) ).toBe(
				'https://example.org/api?q=a%20b&tags=x,y'
			);
		} );
	} );

	describe( 'the wrapper', () => {
		it( 'declines a site API root that is not a URL', () => {
			// The wrapper parses the root at install time, inside the editor's
			// boot sequence, where a throw would replace the editor with the
			// load-error page.
			getGBKit.mockReturnValue( {
				restRelay: REST_RELAY,
				siteApiRoot: 'wp-json/',
			} );

			expect( createRelayFetchWrapper() ).toBeNull();
			expect( warn ).toHaveBeenCalledWith(
				expect.stringContaining( 'wp-json/' )
			);
		} );

		it( 'declines when no relay is advertised', () => {
			getGBKit.mockReturnValue( {
				siteApiRoot: 'https://example.com/wp-json/',
			} );

			expect( createRelayFetchWrapper() ).toBeNull();
		} );

		it( 'wraps when a relay is advertised', async () => {
			getGBKit.mockReturnValue( {
				restRelay: REST_RELAY,
				siteApiRoot: 'https://example.com/wp-json/',
			} );

			await createRelayFetchWrapper()( next )(
				'https://example.com/wp-json/wp/v2/posts'
			);

			expect( calledURL() ).toBe( `${ RELAY_ROOT }wp/v2/posts` );
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
