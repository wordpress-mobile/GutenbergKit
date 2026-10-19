import { Blob as NodeBlob } from 'node:buffer';
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { createRelayFetch, createRelayFetchWrapper } from './fetch-relay';
import { getGBKit } from './bridge';

vi.mock( './bridge', () => ( {
	getGBKit: vi.fn(),
} ) );

vi.mock( './logger', () => ( {
	debug: vi.fn(),
	info: vi.fn(),
	warn: vi.fn(),
	error: vi.fn(),
} ) );

const ENDPOINT = 'gbk-rest://relay/fetch';
const REST_RELAY = { endpoint: ENDPOINT };

/**
 * The relay URL a request is sent to.
 *
 * @param {string} url The request's URL.
 * @return {string} The relay's URL for it.
 */
function relayed( url ) {
	return `${ ENDPOINT }?url=${ encodeURIComponent( url ) }`;
}

describe( 'createRelayFetch', () => {
	let next;

	beforeEach( () => {
		next = vi.fn( () => Promise.resolve( 'response' ) );
	} );

	/**
	 * The wrapper under test, over the shared `next` spy.
	 *
	 * @return {typeof fetch} The wrapped fetch.
	 */
	function relayFetch() {
		return createRelayFetch( next, { restRelay: REST_RELAY } );
	}

	/** The URL `next` was called with. */
	function calledURL() {
		return next.mock.calls[ 0 ][ 0 ];
	}

	describe( 'requests it relays', () => {
		it( 'sends a site API request to the relay, with its URL', async () => {
			const url = 'https://example.com/wp-json/wp/v2/posts?x=1';
			await relayFetch()( url );

			expect( calledURL() ).toBe( relayed( url ) );
		} );

		it( 'sends a request for another host to the relay the same way', async () => {
			// Native code decides how each is sent, so the page doesn't tell
			// them apart.
			const url =
				'https://public-api.wordpress.com/wpcom/v2/jetpack-ai-query?stream=true';
			await relayFetch()( url, {
				method: 'POST',
				body: '{"question":"Hi"}',
			} );

			expect( calledURL() ).toBe( relayed( url ) );
			const init = next.mock.calls[ 0 ][ 1 ];
			expect( init.method ).toBe( 'POST' );
			expect( init.body ).toBe( '{"question":"Hi"}' );
		} );

		it( "keeps the caller's Authorization and sends no cookies", async () => {
			// Jetpack AI signs its requests to WordPress.com with a token of its
			// own. Native code sends a caller's own token as it is, and adds the
			// site credential only to a site API request that has none.
			await relayFetch()( 'https://example.com/wp-json/wp/v2/posts', {
				headers: { Authorization: 'Bearer own-token', 'X-Other': '1' },
			} );

			const init = next.mock.calls[ 0 ][ 1 ];
			const headers = new Headers( init.headers );
			expect( headers.get( 'Authorization' ) ).toBe( 'Bearer own-token' );
			expect( headers.get( 'X-Other' ) ).toBe( '1' );
			expect( init.credentials ).toBe( 'omit' );
		} );

		it( 'sends the whole URL, query and all', async () => {
			await relayFetch()( 'https://example.org/api?q=a%20b&tags=x,y' );

			const relay = new URL( calledURL() );
			expect( relay.searchParams.get( 'url' ) ).toBe(
				'https://example.org/api?q=a%20b&tags=x,y'
			);
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
			await expectPassthrough(
				relayed( 'https://example.com/wp-json/wp/v2/posts' )
			);
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

		it( 'a URL with a user name or password, for fetch itself to refuse', async () => {
			await expectPassthrough( 'https://user:pass@example.org/api' );
			await expectPassthrough( 'https://user@example.org/api' );
		} );

		it( "a request to the page's own origin, which CORS doesn't apply to", async () => {
			// A dev server's, when the editor is loaded from one.
			await expectPassthrough(
				`${ window.location.origin }/src/translations.json`
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

	describe( 'the wrapper', () => {
		it( 'declines when no relay is advertised', () => {
			getGBKit.mockReturnValue( {
				siteApiRoot: 'https://example.com/wp-json/',
			} );

			expect( createRelayFetchWrapper() ).toBeNull();
		} );

		it( 'wraps when a relay is advertised', async () => {
			getGBKit.mockReturnValue( { restRelay: REST_RELAY } );

			const url = 'https://example.com/wp-json/wp/v2/posts';
			await createRelayFetchWrapper()( next )( url );

			expect( calledURL() ).toBe( relayed( url ) );
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
