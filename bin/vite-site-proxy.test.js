// @vitest-environment node

/**
 * External dependencies
 */
import http from 'http';
import { describe, it, expect, beforeAll, afterAll } from 'vitest';

/**
 * Internal dependencies
 */
import {
	SITE_PROXY_PATH,
	proxySiteRequest,
	resolveTarget,
	rewriteSiteUrls,
} from './vite-site-proxy';

describe( 'resolveTarget', () => {
	it( 'resolves a REST API request', () => {
		const target = resolveTarget(
			'/https/example.com/wp-json/wp/v2/posts?page=2',
			'localhost:5173'
		);

		expect( target.upstream.href ).toBe(
			'https://example.com/wp-json/wp/v2/posts?page=2'
		);
		expect( target.origins ).toEqual( [ 'https://example.com' ] );
	} );

	it.each( [
		[
			'a WordPress.com API request',
			'/https/public-api.wordpress.com/wp/v2/sites/1/posts',
		],
		[
			'an AJAX request',
			'/https/example.com/blog/wp-admin/admin-ajax.php',
		],
		[
			'a plain-permalink REST request',
			'/https/example.com/?rest_route=/wp/v2/posts',
		],
	] )( 'allows %s', ( _label, url ) => {
		expect( resolveTarget( url, 'localhost:5173' ) ).not.toBeNull();
	} );

	it.each( [
		[ 'a non-API path', '/https/example.com/wp-admin/options.php' ],
		[ 'an unsupported scheme', '/ftp/example.com/wp-json/' ],
		[ 'a malformed target', '/https' ],
	] )( 'rejects %s', ( _label, url ) => {
		expect( resolveTarget( url, 'localhost:5173' ) ).toBeNull();
	} );

	it( 'reaches a site on the dev server host through localhost', () => {
		const target = resolveTarget(
			'/http/10.0.2.2:8888/wp-json/',
			'10.0.2.2:5173'
		);

		expect( target.upstream.href ).toBe( 'http://localhost:8888/wp-json/' );
		expect( target.origins ).toEqual( [
			'http://10.0.2.2:8888',
			'http://localhost:8888',
		] );
	} );
} );

describe( 'rewriteSiteUrls', () => {
	it( 'points site URLs at the proxy', () => {
		expect(
			rewriteSiteUrls(
				'<https://example.com/wp-json/wp/v2/posts?page=2>; rel="next"',
				[ 'https://example.com' ],
				'http://localhost:5173/__site-proxy/https/example.com'
			)
		).toBe(
			'<http://localhost:5173/__site-proxy/https/example.com/wp-json/wp/v2/posts?page=2>; rel="next"'
		);
	} );

	it( 'leaves other origins unchanged', () => {
		expect(
			rewriteSiteUrls(
				'https://example.com.evil.com/',
				[ 'https://example.com' ],
				'http://localhost:5173/__site-proxy/https/example.com'
			)
		).toBe( 'https://example.com.evil.com/' );
	} );
} );

describe( 'proxySiteRequest', () => {
	let upstream;
	let proxy;
	let received;

	beforeAll( async () => {
		upstream = http.createServer( ( req, res ) => {
			let body = '';
			req.on( 'data', ( chunk ) => ( body += chunk ) );
			req.on( 'end', () => {
				received = {
					method: req.method,
					url: req.url,
					headers: req.headers,
					body,
				};
				const { port } = upstream.address();
				res.writeHead( 200, {
					'Content-Type': 'application/json',
					Link: `<http://localhost:${ port }/wp-json/wp/v2/posts?page=2>; rel="next"`,
				} );
				res.end( '{"ok":true}' );
			} );
		} );
		proxy = http.createServer( ( req, res ) => {
			req.url = req.url.slice( SITE_PROXY_PATH.length );
			proxySiteRequest( req, res );
		} );
		await Promise.all(
			[ upstream, proxy ].map(
				( server ) =>
					new Promise( ( resolve ) =>
						server.listen( 0, 'localhost', resolve )
					)
			)
		);
	} );

	afterAll( () => {
		upstream.close();
		proxy.close();
	} );

	const proxyUrl = ( path ) =>
		`http://localhost:${
			proxy.address().port
		}${ SITE_PROXY_PATH }/http/localhost:${
			upstream.address().port
		}${ path }`;

	it( 'forwards the request and returns the response', async () => {
		const response = await fetch( proxyUrl( '/wp-json/wp/v2/posts' ), {
			method: 'POST',
			headers: {
				Authorization: 'Bearer token',
				'Content-Type': 'application/json',
				Origin: 'http://localhost:5173',
				Cookie: 'dev=1',
			},
			body: '{"title":"Hello"}',
		} );

		expect( response.status ).toBe( 200 );
		expect( await response.json() ).toEqual( { ok: true } );
		expect( received ).toMatchObject( {
			method: 'POST',
			url: '/wp-json/wp/v2/posts',
			body: '{"title":"Hello"}',
		} );
		expect( received.headers.authorization ).toBe( 'Bearer token' );
		expect( received.headers.host ).toBe(
			`localhost:${ upstream.address().port }`
		);
		expect( received.headers.origin ).toBeUndefined();
		expect( received.headers.cookie ).toBeUndefined();
	} );

	it( 'keeps pagination links on the proxy', async () => {
		const response = await fetch( proxyUrl( '/wp-json/wp/v2/posts' ) );

		expect( response.headers.get( 'link' ) ).toBe(
			`<${ proxyUrl( '/wp-json/wp/v2/posts?page=2' ) }>; rel="next"`
		);
	} );

	it( 'refuses requests outside the WordPress APIs', async () => {
		const response = await fetch( proxyUrl( '/wp-admin/' ) );

		expect( response.status ).toBe( 403 );
	} );
} );
