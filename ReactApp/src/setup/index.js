/**
 * WordPress dependencies
 */
import apiFetch from '@wordpress/api-fetch';

/**
 * Internal dependencies
 */
import { getGBKit } from '../misc/store.js';
import { initializeApiFetch } from '../misc/api-fetch-setup';

window.GBKit = getGBKit();
window.wp = window.wp || {};
window.wp.apiFetch = apiFetch;
initializeApiFetch();
