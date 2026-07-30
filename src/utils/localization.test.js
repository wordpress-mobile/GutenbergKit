/**
 * External dependencies
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';

/**
 * WordPress dependencies
 */
import { setLocaleData } from '@wordpress/i18n';

/**
 * Internal dependencies
 */
import { configureLocale, isRTLLocale } from './localization';
import { getGBKit } from './bridge';

vi.mock( './bridge' );
vi.mock( './logger' );

vi.mock( '@wordpress/i18n', () => ( {
	setLocaleData: vi.fn(),
} ) );

// The gettext context separator joining a string's context to its msgid.
const TEXT_DIRECTION_KEY = `text direction${ String.fromCharCode( 4 ) }ltr`;

describe( 'isRTLLocale', () => {
	it.each( [ 'ar', 'fa', 'he', 'ur' ] )(
		'identifies %s as right-to-left',
		( locale ) => {
			expect( isRTLLocale( locale ) ).toBe( true );
		}
	);

	it.each( [ 'en', 'fr', 'ja', 'pt-br', 'zh-cn', 'nl-be' ] )(
		'identifies %s as left-to-right',
		( locale ) => {
			expect( isRTLLocale( locale ) ).toBe( false );
		}
	);

	it( 'matches on the base language subtag for regional variants', () => {
		// No regional RTL bundle ships today, but direction is a property of
		// the language, so a future `ar-dz` bundle must not regress to LTR.
		expect( isRTLLocale( 'ar-dz' ) ).toBe( true );
		expect( isRTLLocale( 'ar_DZ' ) ).toBe( true );
	} );

	it( 'is case insensitive', () => {
		expect( isRTLLocale( 'AR' ) ).toBe( true );
		expect( isRTLLocale( 'He' ) ).toBe( true );
	} );

	it( 'treats missing locales as left-to-right', () => {
		expect( isRTLLocale( undefined ) ).toBe( false );
		expect( isRTLLocale( '' ) ).toBe( false );
	} );
} );

describe( 'configureLocale', () => {
	beforeEach( () => {
		vi.clearAllMocks();
		document.documentElement.removeAttribute( 'lang' );
		document.documentElement.removeAttribute( 'dir' );
		document.body.classList.remove( 'rtl' );
	} );

	it( 'applies right-to-left direction for an RTL locale', async () => {
		getGBKit.mockReturnValue( { locale: 'ar' } );

		await configureLocale();

		expect( document.documentElement.dir ).toBe( 'rtl' );
		expect( document.documentElement.lang ).toBe( 'ar' );
		expect( document.body.classList.contains( 'rtl' ) ).toBe( true );
	} );

	it( 'applies left-to-right direction for an LTR locale', async () => {
		getGBKit.mockReturnValue( { locale: 'fr' } );

		await configureLocale();

		expect( document.documentElement.dir ).toBe( 'ltr' );
		expect( document.documentElement.lang ).toBe( 'fr' );
		expect( document.body.classList.contains( 'rtl' ) ).toBe( false );
	} );

	it( 'defaults to English left-to-right when no locale is provided', async () => {
		getGBKit.mockReturnValue( {} );

		await configureLocale();

		expect( document.documentElement.dir ).toBe( 'ltr' );
		expect( document.documentElement.lang ).toBe( 'en' );
	} );

	it( 'removes a stale rtl body class when switching to an LTR locale', async () => {
		document.body.classList.add( 'rtl' );
		getGBKit.mockReturnValue( { locale: 'en' } );

		await configureLocale();

		expect( document.body.classList.contains( 'rtl' ) ).toBe( false );
	} );

	// `isRTL()` resolves to `_x( 'ltr', 'text direction' )`. The bundles we
	// fetch from the `wp-plugins/gutenberg` GlotPress project don't carry that
	// string — it belongs to core — so it must be injected for the Gutenberg
	// components that branch on direction at runtime.
	it( 'injects the text direction string that backs isRTL()', async () => {
		getGBKit.mockReturnValue( { locale: 'he' } );

		await configureLocale();

		expect( setLocaleData ).toHaveBeenCalledWith( {
			[ TEXT_DIRECTION_KEY ]: [ 'rtl' ],
		} );
	} );

	it( 'injects ltr for left-to-right locales', async () => {
		getGBKit.mockReturnValue( { locale: 'de' } );

		await configureLocale();

		expect( setLocaleData ).toHaveBeenCalledWith( {
			[ TEXT_DIRECTION_KEY ]: [ 'ltr' ],
		} );
	} );
} );
