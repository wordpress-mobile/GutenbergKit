/**
 * Wraps a module namespace the way core builds its `window.wp` globals.
 *
 * Core's esbuild `__toCommonJS` flags each exports object `__esModule`, which
 * plugin bundlers read to resolve a default import to `default`.
 *
 * @param {Object} namespace Module namespace object.
 * @return {Object} Exports object with a non-enumerable `__esModule` flag.
 */
export function toCommonJS( namespace ) {
	const exports = Object.defineProperty( {}, '__esModule', { value: true } );
	for ( const key of Object.keys( namespace ) ) {
		Object.defineProperty( exports, key, {
			enumerable: true,
			get: () => namespace[ key ],
		} );
	}
	return exports;
}
