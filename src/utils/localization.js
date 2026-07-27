/**
 * WordPress dependencies
 */
import { setLocaleData } from '@wordpress/i18n';

/**
 * Internal dependencies
 */
import { getGBKit } from './bridge';
import { warn, debug } from './logger';

const DEFAULT_LOCALE = 'en';

// Vite statically enumerates the translation bundles at build time, so the
// loader map below is always in sync with what we actually ship.
const TRANSLATION_MODULES = import.meta.glob( '../translations/*.json' );

// Right-to-left locales among the bundles we ship. Direction is a fixed
// property of a language, and the native side has already resolved the
// consumer-supplied locale to one of these tags before it reaches JS, so
// deriving direction here always agrees with the translations we load.
//
// Kept as base language tags: no regional bundle we ship (`ar`, `fa`, `he`,
// `ur` have none) splits across directions, and matching on the base tag
// keeps this correct if a regional RTL bundle is added later.
const RTL_LOCALES = new Set( [ 'ar', 'fa', 'he', 'ur' ] );

// The key `@wordpress/i18n` reads for `isRTL()`, which resolves to
// `_x( 'ltr', 'text direction' )`. The `\u0004` escape is the gettext
// context separator joining a string's context to its msgid; written as an
// escape so the control character stays visible in source.
const TEXT_DIRECTION_KEY = 'text direction\u0004ltr';

/**
 * Initializes i18n support for the editor.
 *
 * @return {Promise<void>} A promise that resolves when i18n is initialized.
 */
export async function configureLocale() {
	const { locale = DEFAULT_LOCALE } = getGBKit();
	await loadTranslations( locale );
	configureTextDirection( locale );
}

/**
 * Determines whether a locale is written right-to-left.
 *
 * @param {string} locale The locale to check.
 *
 * @return {boolean} Whether the locale is right-to-left.
 */
export function isRTLLocale( locale ) {
	if ( ! locale ) {
		return false;
	}

	// Match on the base language subtag so regional variants (e.g. `ar-dz`)
	// resolve correctly even though we don't currently ship any.
	const [ language ] = locale.toLowerCase().split( /[-_]/ );
	return RTL_LOCALES.has( language );
}

/**
 * Applies the locale's text direction to the document and to `@wordpress/i18n`.
 *
 * In WordPress, core renders `<html lang dir>` and `<body class="rtl">`, and
 * populates the `text direction` string that backs `isRTL()`. GutenbergKit
 * loads a static `index.html`, so nothing performs that role and the editor
 * would otherwise render every locale as English left-to-right.
 *
 * Both halves matter. The DOM attributes drive CSS logical properties, bidi
 * text runs, and native spellcheck/screen-reader behavior. The `setLocaleData`
 * entry drives `isRTL()`, which Gutenberg components call at runtime to pick
 * icons, accessibility labels, keyboard navigation, and drop-zone geometry —
 * none of which CSS can correct.
 *
 * The translation bundles we ship come from the `wp-plugins/gutenberg` GlotPress
 * project, which does not carry the `text direction` string (it belongs to
 * core), so the entry is injected here rather than read from the bundle.
 *
 * @param {string} locale The locale in use.
 *
 * @return {void}
 */
function configureTextDirection( locale ) {
	const isRTL = isRTLLocale( locale );
	const direction = isRTL ? 'rtl' : 'ltr';

	// Back `isRTL()` for Gutenberg's runtime direction checks.
	setLocaleData( { [ TEXT_DIRECTION_KEY ]: [ direction ] } );

	const { documentElement, body } = document;

	documentElement.lang = locale;
	documentElement.dir = direction;

	// Some Gutenberg styles key off `body.rtl` rather than `[dir=rtl]`.
	body?.classList.toggle( 'rtl', isRTL );

	debug( `Text direction configured as "${ direction }" for "${ locale }"` );
}

/**
 * Loads translations for the specified locale from the bundled files.
 *
 * The native side is responsible for resolving consumer-supplied locales to a
 * shipped tag before the value reaches JS. Anything that doesn't match a
 * bundled translation falls back to English.
 *
 * @param {string} locale The locale to load translations for.
 *
 * @return {Promise<void>} A promise that resolves when translations are loaded.
 */
async function loadTranslations( locale ) {
	if ( locale === DEFAULT_LOCALE ) {
		return;
	}

	const loader = TRANSLATION_MODULES[ `../translations/${ locale }.json` ];
	if ( ! loader ) {
		warn(
			`Translations unavailable for locale "${ locale }". Falling back to English.`
		);
		return;
	}

	try {
		debug( 'Loading translations for', locale );
		const { default: translations } = await loader();
		setLocaleData( translations );
	} catch ( err ) {
		warn(
			`Translations unavailable for locale "${ locale }". Falling back to English.`
		);
		debug( 'Translation loading error details:', err );
	}
}
