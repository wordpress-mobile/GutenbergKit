/**
 * External dependencies
 */
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';

/**
 * Internal dependencies
 */
import { installFetchWrappers } from './fetch-chain';

vi.mock( './logger', () => ( {
	debug: vi.fn(),
	info: vi.fn(),
	warn: vi.fn(),
	error: vi.fn(),
} ) );

describe( 'installFetchWrappers', () => {
	let originalFetch;
	let calls;

	beforeEach( () => {
		originalFetch = window.fetch;
		calls = [];
		window.fetch = vi.fn( () => {
			calls.push( 'fetch' );
			return Promise.resolve( 'response' );
		} );
	} );

	afterEach( () => {
		window.fetch = originalFetch;
	} );

	/**
	 * A wrapper that records when it runs, relative to the others.
	 *
	 * @param {string} name Recorded on the way in and out.
	 * @return {import('./fetch-chain').FetchWrapper} The wrapper.
	 */
	function recorder( name ) {
		return ( next ) => async ( input, init ) => {
			calls.push( `${ name }:in` );
			const response = await next( input, init );
			calls.push( `${ name }:out` );
			return response;
		};
	}

	it( 'runs wrappers outermost first and unwinds in reverse', async () => {
		installFetchWrappers( [ recorder( 'a' ), recorder( 'b' ) ] );

		await window.fetch( 'https://example.com/' );

		expect( calls ).toEqual( [
			'a:in',
			'b:in',
			'fetch',
			'b:out',
			'a:out',
		] );
	} );

	it( 'passes the request through the chain to the underlying fetch', async () => {
		const rewrite = ( next ) => ( input, init ) =>
			next( `${ input }rewritten`, init );
		installFetchWrappers( [ recorder( 'a' ), rewrite ] );

		await window.fetch( 'https://example.com/', { method: 'POST' } );

		expect( window.fetch ).not.toBe( originalFetch );
		expect( calls ).toEqual( [ 'a:in', 'fetch', 'a:out' ] );
	} );

	it( 'skips entries that reported themselves inapplicable', async () => {
		installFetchWrappers( [ null, recorder( 'a' ), null ] );

		await window.fetch( 'https://example.com/' );

		expect( calls ).toEqual( [ 'a:in', 'fetch', 'a:out' ] );
	} );

	it( 'leaves fetch untouched when nothing applies', () => {
		const before = window.fetch;

		installFetchWrappers( [ null, null ] );

		expect( window.fetch ).toBe( before );
	} );
} );
