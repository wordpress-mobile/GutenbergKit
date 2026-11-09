import { speak } from '@wordpress/a11y';
import { Icon } from '@wordpress/components';
import { useState, useEffect } from '@wordpress/element';
import { __ } from '@wordpress/i18n';
import { Path, SVG } from '@wordpress/primitives';
import { getGBKit } from '../../utils/bridge';
import './style.scss';

// Copied from `@wordpress/icons`, which removed it in v20 with no replacement
// (https://github.com/WordPress/gutenberg/pull/85445).
const offline = (
	<SVG
		xmlns="http://www.w3.org/2000/svg"
		viewBox="0 0 24 24"
		fill="currentColor"
	>
		<Path d="M 2.05 4.22 L 3.45 2.81 L 20.34 19.78 L 18.94 21.19 L 11.89 14.11 C 10.12 14.13 8.37 14.82 7.02 16.17 L 5.03 14.17 C 6.3 12.91 7.81 12.06 9.42 11.63 L 7.19 9.39 C 5.68 10.01 4.27 10.94 3.04 12.17 L 1.05 10.17 C 2.27 8.96 3.63 8 5.08 7.27 L 2.05 4.22 M 22.95 10.17 L 20.96 12.17 C 18.46 9.66 15.16 8.42 11.88 8.44 L 9.31 5.86 C 14.12 5.02 19.23 6.44 22.95 10.17 M 15.26 11.84 C 16.62 12.32 17.89 13.09 18.97 14.17 L 18.27 14.86 L 15.26 11.84 M 9.01 18.17 L 12 21.17 L 14.99 18.17 C 13.34 16.51 10.67 16.51 9.01 18.17" />
	</SVG>
);

/**
 * Displays a thin status bar when the device is offline.
 *
 * The indicator automatically shows/hides based on the browser's online/offline
 * events — no manual dismiss needed.
 *
 * @return {?Element} The rendered component or null when online.
 */
export default function OfflineIndicator() {
	const { isConnected } = useNetworkConnectivity();

	useEffect( () => {
		if ( ! isConnected ) {
			speak(
				__(
					'Network connection lost, working offline',
					'gutenberg-kit'
				),
				'assertive'
			);
		}
	}, [ isConnected ] );

	if ( isConnected ) {
		return null;
	}

	return (
		<div className="gutenberg-kit-offline-indicator">
			<Icon icon={ offline } size={ 18 } />
			{ __( 'Working Offline', 'gutenberg-kit' ) }
		</div>
	);
}

/**
 * Tracks network connectivity using browser online/offline events verified by
 * a real HTTP probe.
 *
 * The `offline` event is treated as immediately authoritative. The `online`
 * event triggers a probe to confirm actual connectivity before clearing the
 * indicator, guarding against false positives from `navigator.onLine`.
 *
 * Initial state reads `navigator.onLine` but only trusts `false` — a definitive
 * signal the browser has no network interface. A `true` value is not trusted on
 * its own; Chrome is known to misreport it. If the browser reports online at
 * mount, a probe runs immediately to verify before committing to that state.
 *
 * @return {{ isConnected: boolean }} Whether the device is currently connected.
 */
function useNetworkConnectivity() {
	const [ isConnected, setIsConnected ] = useState( navigator.onLine );

	useEffect( () => {
		const abortController = new AbortController();

		// If the browser reports online at mount, probe immediately to catch
		// Chrome incorrectly reporting navigator.onLine as true.
		if ( navigator.onLine ) {
			probeConnectivity().then( ( connected ) => {
				if ( ! abortController.signal.aborted ) {
					setIsConnected( connected );
				}
			} );
		}

		const handleOnline = async () => {
			const connected = await probeConnectivity();
			if ( ! abortController.signal.aborted ) {
				setIsConnected( connected );
			}
		};
		const handleOffline = () => setIsConnected( false );

		window.addEventListener( 'online', handleOnline );
		window.addEventListener( 'offline', handleOffline );

		return () => {
			abortController.abort();
			window.removeEventListener( 'online', handleOnline );
			window.removeEventListener( 'offline', handleOffline );
		};
	}, [] );

	return { isConnected };
}

/**
 * Probes real internet connectivity by making a lightweight HEAD request.
 *
 * `navigator.onLine` and the browser `online` event are unreliable — they only
 * confirm a network interface is active, not that the internet is reachable.
 * This probe verifies actual connectivity before reporting online status.
 *
 * @return {Promise<boolean>} Whether the probe request succeeded.
 */
async function probeConnectivity() {
	try {
		await window.fetch( getConnectivityProbeUrl(), {
			method: 'HEAD',
			mode: 'no-cors',
			cache: 'no-store',
			signal: AbortSignal.timeout( 5000 ),
		} );
		return true;
	} catch {
		return false;
	}
}

/**
 * Returns a URL suitable for probing real internet connectivity.
 *
 * Prefers the site API root so the probe reflects whether the WordPress API
 * specifically is reachable. Falls back to `/favicon.ico` for local dev
 * environments where no GBKit config is available.
 *
 * @return {string} The probe URL.
 */
function getConnectivityProbeUrl() {
	const { siteApiRoot } = getGBKit();
	return siteApiRoot || '/favicon.ico';
}
