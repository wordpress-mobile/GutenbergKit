/**
 * Internal dependencies
 */
import { debug } from './logger';

/**
 * Marks the wrapped `fetch` as ours. Registered globally so a second copy of
 * this module — a re-injected bundle — recognizes the mark rather than wrapping
 * an already-wrapped `fetch`.
 */
const WRAPPED = Symbol.for( 'gutenbergkit.fetchWrappers' );

/**
 * A transform on `fetch`: given the fetch to delegate to, returns a fetch.
 *
 * The same shape as an `apiFetch` middleware, one layer down. A wrapper may
 * change where the request goes, observe it, or decline to touch it and hand it
 * straight to `next`.
 *
 * @typedef {(next: typeof fetch) => typeof fetch} FetchWrapper
 */

/**
 * Wraps the global `fetch` with a chain of wrappers, outermost first.
 *
 * `[ a, b ]` produces `a( b( fetch ) )`, so `a` sees the request first and the
 * response last. Order is behavior, not preference: a wrapper that rewrites the
 * request changes what every wrapper inside it observes, so the network log has
 * to sit outside the relay to record the request the editor made rather than
 * the loopback rewrite of it.
 *
 * Entries that are `null` are skipped, so a wrapper module can report "not
 * applicable" — network logging switched off, no relay configured — by
 * returning nothing rather than by installing a pass-through.
 *
 * Installing twice is a no-op. A retried boot or a re-injected bundle would
 * otherwise wrap the wrapped `fetch`, logging every request to the native host
 * twice and sending it through two relay layers. A page load resets this along
 * with `window.fetch` itself.
 *
 * @param {Array<FetchWrapper|null>} wrappers The chain, outermost first.
 * @return {void}
 */
export function installFetchWrappers( wrappers ) {
	const active = wrappers.filter( Boolean );

	if ( ! active.length ) {
		return;
	}

	if ( window.fetch[ WRAPPED ] ) {
		debug( 'Fetch wrappers are already installed' );
		return;
	}

	const wrapped = active.reduceRight(
		( next, wrap ) => wrap( next ),
		window.fetch.bind( window )
	);
	wrapped[ WRAPPED ] = true;
	window.fetch = wrapped;
	debug( `Installed ${ active.length } fetch wrapper(s)` );
}
