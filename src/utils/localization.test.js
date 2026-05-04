/**
 * External dependencies
 */
import { describe, it, expect, vi } from 'vitest';

vi.mock( './logger.js', () => ( {
	error: vi.fn(),
	warn: vi.fn(),
	info: vi.fn(),
	debug: vi.fn(),
} ) );

/**
 * Internal dependencies
 */
import { resolveLocale } from './localization';

// Stand-in for the manifest emitted at build time. Mirrors the real
// supported set closely enough to exercise both fallback steps.
const SUPPORTED = [
	'de',
	'en-gb',
	'es',
	'es-ar',
	'fr',
	'nl',
	'nl-be',
	'pt',
	'pt-br',
	'zh-cn',
	'zh-tw',
];

describe( 'resolveLocale', () => {
	it( 'returns "en" for null/empty input', () => {
		expect( resolveLocale( null, SUPPORTED ) ).toBe( 'en' );
		expect( resolveLocale( undefined, SUPPORTED ) ).toBe( 'en' );
		expect( resolveLocale( '', SUPPORTED ) ).toBe( 'en' );
	} );

	it( 'matches the full normalized tag when shipped', () => {
		expect( resolveLocale( 'pt-br', SUPPORTED ) ).toBe( 'pt-br' );
		expect( resolveLocale( 'pt-BR', SUPPORTED ) ).toBe( 'pt-br' );
		expect( resolveLocale( 'pt_BR', SUPPORTED ) ).toBe( 'pt-br' );
		expect( resolveLocale( 'zh-CN', SUPPORTED ) ).toBe( 'zh-cn' );
		expect( resolveLocale( 'EN_GB', SUPPORTED ) ).toBe( 'en-gb' );
	} );

	it( 'falls back to the language-only tag when the regional bundle is absent', () => {
		// `fr-CA` not shipped, but `fr` is.
		expect( resolveLocale( 'fr-CA', SUPPORTED ) ).toBe( 'fr' );
		// `de-AT` not shipped, but `de` is.
		expect( resolveLocale( 'de-AT', SUPPORTED ) ).toBe( 'de' );
	} );

	it( 'falls back to "en" when neither full nor language match', () => {
		// We ship `zh-cn`/`zh-tw` but no language-only `zh`, so a bare
		// `zh` from a device locale should land on English. This is the
		// real-world footgun the issue calls out.
		expect( resolveLocale( 'zh', SUPPORTED ) ).toBe( 'en' );
		expect( resolveLocale( 'xx-yy', SUPPORTED ) ).toBe( 'en' );
	} );
} );
