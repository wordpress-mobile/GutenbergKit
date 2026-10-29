import { describe, it, expect } from 'vitest';
import { toCommonJS } from './to-common-js';

describe( 'toCommonJS', () => {
	const namespace = Object.freeze( {
		default: () => 'default',
		named: () => 'named',
	} );

	it( 'flags the exports object __esModule without enumerating it', () => {
		const exports = toCommonJS( namespace );

		expect( exports.__esModule ).toBe( true );
		expect( Object.keys( exports ) ).toEqual( [ 'default', 'named' ] );
	} );

	it( 'exposes each export by reference', () => {
		const exports = toCommonJS( namespace );

		expect( exports.default ).toBe( namespace.default );
		expect( exports.named ).toBe( namespace.named );
	} );

	// Mirrors webpack's `__webpack_require__.n`, which plugin bundles use for
	// `window.wp` externals.
	it( 'resolves a default import to the default export', () => {
		const getDefaultExport = ( module ) =>
			module && module.__esModule ? module.default : module;

		expect( getDefaultExport( toCommonJS( namespace ) ) ).toBe(
			namespace.default
		);
	} );
} );
