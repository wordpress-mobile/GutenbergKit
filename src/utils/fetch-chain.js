/**
 * Internal dependencies
 */
import { debug } from './logger';

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
 * @param {Array<FetchWrapper|null>} wrappers The chain, outermost first.
 * @return {void}
 */
export function installFetchWrappers( wrappers ) {
	const active = wrappers.filter( Boolean );

	if ( ! active.length ) {
		return;
	}

	window.fetch = active.reduceRight(
		( next, wrap ) => wrap( next ),
		window.fetch.bind( window )
	);
	debug( `Installed ${ active.length } fetch wrapper(s)` );
}
