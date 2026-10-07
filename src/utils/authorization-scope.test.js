import { describe, it, expect } from 'vitest';
import { isWithinAuthorizationScope } from './authorization-scope';

const site = {
	siteURL: 'https://example.com',
	siteApiRoot: 'https://example.com/wp-json/',
};

/**
 * Whether the test site's credentials may go with a request to `url`, when
 * the app names `authHeaderDomains` as well.
 *
 * @param {string}   url               The URL of the request.
 * @param {string[]} authHeaderDomains The places the app names.
 * @return {boolean} Whether the request may carry the credentials.
 */
function allows( url, authHeaderDomains = [] ) {
	return isWithinAuthorizationScope( url, { ...site, authHeaderDomains } );
}

describe( 'isWithinAuthorizationScope', () => {
	describe( 'the site and its API', () => {
		it.each( [
			'https://example.com/wp-json/wp/v2/posts/1?context=edit',
			'https://example.com/wp-admin/admin-ajax.php',
			'https://EXAMPLE.com/wp-content/themes/theme/style.css',
			'https://example.com:443/wp-json/',
		] )( 'allows the site and its REST API: %s', ( url ) => {
			expect( allows( url ) ).toBe( true );
		} );

		it.each( [
			// Another party's host
			'https://api.vendor.net/v1/things',
			// Hosts that only look like the site's
			'https://example.com.vendor.net/v1/things',
			'https://notexample.com/v1/things',
			'https://cdn.example.com/script.js',
			// The site's host, but not the place it was configured with
			'http://example.com/wp-json/wp/v2/posts',
			'https://example.com:8443/wp-json/',
			// Places an app could name, and this one hasn't
			'https://s0.wp.com/wp-content/plugins/plugin/script.js',
			'https://example.files.wordpress.com/2026/10/image.png',
			// No site at all
			'/wp-json/wp/v2/posts',
			'file:///wp-content/script.js',
			'data:text/javascript,',
			'',
			undefined,
		] )(
			'refuses everywhere else, unless the app names the place: %s',
			( url ) => {
				expect( allows( url ) ).toBe( false );
			}
		);

		it( 'allows a site served in the clear its own credentials', () => {
			const local = {
				siteURL: 'http://localhost:8881',
				siteApiRoot: 'http://localhost:8881/wp-json/',
			};

			expect(
				isWithinAuthorizationScope(
					'http://localhost:8881/wp-json/wp/v2/posts',
					local
				)
			).toBe( true );
			expect(
				isWithinAuthorizationScope(
					'http://localhost:9999/script.js',
					local
				)
			).toBe( false );
		} );

		it( 'refuses every request when no site is configured', () => {
			expect(
				isWithinAuthorizationScope( 'https://example.com/wp-json/', {} )
			).toBe( false );
			expect(
				isWithinAuthorizationScope( 'https://example.com/wp-json/' )
			).toBe( false );
		} );

		it( "infers nothing from where a site's API is", () => {
			const reachedThroughWordPressDotCom = {
				siteURL: 'https://example.com',
				siteApiRoot: 'https://public-api.wordpress.com/',
			};

			expect(
				isWithinAuthorizationScope(
					'https://s0.wp.com/script.js',
					reachedThroughWordPressDotCom
				)
			).toBe( false );
		} );
	} );

	describe( 'a named host', () => {
		it.each( [
			'https://s0.wp.com/wp-content/plugins/plugin/script.js?m=1',
			'https://S0.WP.com/script.js',
		] )( 'is that host, in any case, over HTTPS: %s', ( url ) => {
			expect( allows( url, [ 'S0.wp.com' ] ) ).toBe( true );
		} );

		it.each( [
			// Its siblings, its subdomains, and the domain it's under
			'https://s1.wp.com/script.js',
			'https://cdn.s0.wp.com/script.js',
			'https://wp.com/script.js',
			// Hosts that only look like it
			'https://s0.wp.com.vendor.net/script.js',
			'https://nots0.wp.com/script.js',
			// The host itself, in the clear
			'http://s0.wp.com/script.js',
		] )( 'is no other host: %s', ( url ) => {
			expect( allows( url, [ 's0.wp.com' ] ) ).toBe( false );
		} );

		// Naming a host never reaches past it, so even a top-level domain
		// names only itself.
		it.each( [ 'com', 'net', 'cool', 'uk' ] )(
			'covers nothing under it, even a top-level domain: %s',
			( domain ) => {
				expect(
					allows( `https://vendor.${ domain }/script.js`, [ domain ] )
				).toBe( false );
				expect(
					allows( `https://cdn.vendor.${ domain }/script.js`, [
						domain,
					] )
				).toBe( false );
			}
		);
	} );

	describe( 'a wildcard', () => {
		const named = [ '*.wp.com', '*.files.wordpress.com' ];

		it.each( [
			'https://wp.com/script.js',
			'https://WP.com/script.js',
			'https://files.wordpress.com/image.png',
			'https://s0.wp.com/wp-content/plugins/plugin/script.js?m=1',
			'https://S1.WP.com/_static/??-eJx9jk',
			'https://i0.wp.com/example.com/image.png',
			'https://a.b.wp.com/script.js',
			'https://example.files.wordpress.com/2026/10/image.png',
			'https://Another.Files.WordPress.com/2026/10/image.png',
		] )(
			"is the domain it's over and every subdomain of it, however deep: %s",
			( url ) => {
				expect( allows( url, named ) ).toBe( true );
			}
		);

		it.each( [
			// Hosts that only look like the domain or its subdomains
			'https://notwp.com/script.js',
			'https://wp.com.vendor.net/script.js',
			'https://files.wordpress.com.vendor.net/image.png',
			'https://notfiles.wordpress.com/image.png',
			// A domain above it
			'https://another.wordpress.com/script.js',
			// The domain and its subdomains, in the clear
			'http://wp.com/script.js',
			'http://s0.wp.com/script.js',
			'http://example.files.wordpress.com/2026/10/image.png',
			// Another party's host
			'https://api.vendor.net/v1/things',
		] )( 'is nothing else: %s', ( url ) => {
			expect( allows( url, named ) ).toBe( false );
		} );

		// What a wildcard is over is the app's business: nothing here
		// second-guesses it.
		it( 'is taken at its word, however much it covers', () => {
			const overTopLevelDomain = [ '*.com' ];

			expect(
				allows( 'https://vendor.com/script.js', overTopLevelDomain )
			).toBe( true );
			expect(
				allows( 'https://cdn.vendor.com/script.js', overTopLevelDomain )
			).toBe( true );
			expect(
				allows( 'https://vendor.net/script.js', overTopLevelDomain )
			).toBe( false );
			expect(
				allows( 'http://vendor.com/script.js', overTopLevelDomain )
			).toBe( false );

			const overRegistry = [ '*.co.uk' ];

			expect(
				allows( 'https://vendor.co.uk/script.js', overRegistry )
			).toBe( true );
			expect(
				allows( 'https://vendor.org.uk/script.js', overRegistry )
			).toBe( false );
		} );
	} );

	describe( 'names', () => {
		it.each( [ '*.wp.com.', ' *.wp.com ' ] )(
			'can end with the dot that ends a fully qualified one: %s',
			( domain ) => {
				expect(
					allows( 'https://s0.wp.com/script.js', [ domain ] )
				).toBe( true );
			}
		);

		it.each( [
			'',
			' ',
			'*',
			'*.',
			'.',
			// Only `*.` in front is a wildcard
			'.wp.com',
			's*.wp.com',
			'*wp.com',
			'wp.*',
			's0.*.com',
			'*.*.com',
			'*.*.wp.com',
			// Not a host
			'wp..com',
			'https://s0.wp.com',
			null,
			undefined,
		] )(
			'name nowhere when neither a host nor a wildcard over a domain: %s',
			( domain ) => {
				for ( const url of [
					'https://s0.wp.com/script.js',
					'https://wp.com/script.js',
					'https://api.vendor.net/v1/things',
				] ) {
					expect( allows( url, [ domain ] ) ).toBe( false );
				}
			}
		);
	} );
} );
