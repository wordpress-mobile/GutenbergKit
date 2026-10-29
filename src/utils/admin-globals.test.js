import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { configureAdminGlobals } from './admin-globals';
import { getGBKit } from './bridge';

vi.mock( './bridge', async ( importOriginal ) => ( {
	...( await importOriginal() ),
	getGBKit: vi.fn(),
} ) );

const GLOBALS = [ 'ajaxurl', 'pagenow', 'typenow', 'adminpage', 'isRtl' ];

describe( 'configureAdminGlobals', () => {
	beforeEach( () => {
		GLOBALS.forEach( ( name ) => delete window[ name ] );
	} );

	afterEach( () => {
		GLOBALS.forEach( ( name ) => delete window[ name ] );
	} );

	it( 'defines the screen globals for an existing post', () => {
		getGBKit.mockReturnValue( {
			siteURL: 'https://example.com/',
			post: { id: 42, type: 'page' },
		} );

		configureAdminGlobals();

		expect( window ).toMatchObject( {
			ajaxurl: 'https://example.com/wp-admin/admin-ajax.php',
			pagenow: 'page',
			typenow: 'page',
			adminpage: 'post-php',
			isRtl: 0,
		} );
	} );

	it( 'omits the number separator globals', () => {
		getGBKit.mockReturnValue( {} );

		configureAdminGlobals();

		expect( window ).not.toHaveProperty( 'thousandsSeparator' );
		expect( window ).not.toHaveProperty( 'decimalPoint' );
	} );

	it.each( [ undefined, -1, 0 ] )(
		'treats a post with ID %s as new',
		( id ) => {
			getGBKit.mockReturnValue( { post: { id, type: 'post' } } );

			configureAdminGlobals();

			expect( window.adminpage ).toBe( 'post-new-php' );
		}
	);

	it( 'falls back to the post type when none is provided', () => {
		getGBKit.mockReturnValue( {} );

		configureAdminGlobals();

		expect( window.pagenow ).toBe( 'post' );
		expect( window.typenow ).toBe( 'post' );
		expect( window.ajaxurl ).toBeUndefined();
	} );

	it( 'flags a right-to-left editor', () => {
		getGBKit.mockReturnValue( {} );

		configureAdminGlobals( true );

		expect( window.isRtl ).toBe( 1 );
	} );
} );
