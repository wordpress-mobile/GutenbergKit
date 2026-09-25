/**
 * External dependencies
 */
import { describe, it, expect } from 'vitest';

/**
 * Internal dependencies
 */
import { ensureTrailingSlash, stripTrailingSlash } from './url';

describe( 'stripTrailingSlash', () => {
	it.each( [
		[ 'https://example.com/wp-json/', 'https://example.com/wp-json' ],
		[ 'https://example.com/wp-json//', 'https://example.com/wp-json' ],
		[ 'https://example.com/wp-json', 'https://example.com/wp-json' ],
		[ 'sites/123/', 'sites/123' ],
		[ '/', '' ],
		[ '', '' ],
		[ undefined, '' ],
		[ null, '' ],
	] )( 'normalizes %s to %s', ( value, expected ) => {
		expect( stripTrailingSlash( value ) ).toBe( expected );
	} );

	// An absent value is expected; a wrong type is a caller bug worth surfacing.
	it( 'throws on a non-string', () => {
		expect( () => stripTrailingSlash( 42 ) ).toThrow( TypeError );
	} );
} );

describe( 'ensureTrailingSlash', () => {
	it.each( [
		[ 'https://example.com/wp-json', 'https://example.com/wp-json/' ],
		[ 'https://example.com/wp-json/', 'https://example.com/wp-json/' ],
		[ 'https://example.com/wp-json//', 'https://example.com/wp-json/' ],
		[ 'sites/123', 'sites/123/' ],
		// A lone slash is a meaningful root, unlike an absent value.
		[ '/', '/' ],
		[ '', '' ],
		[ undefined, '' ],
		[ null, '' ],
	] )( 'normalizes %s to %s', ( value, expected ) => {
		expect( ensureTrailingSlash( value ) ).toBe( expected );
	} );

	it( 'throws on a non-string', () => {
		expect( () => ensureTrailingSlash( 42 ) ).toThrow( TypeError );
	} );
} );
