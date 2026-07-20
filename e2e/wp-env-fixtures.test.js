/**
 * External dependencies
 */
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';

/**
 * Internal dependencies
 */
import { fetchJson } from './wp-env-fixtures';

const CREDS = { authHeader: 'Basic dGVzdDp0ZXN0' };
const URL = 'http://localhost/wp-json/wp-block-editor/v1/settings';

const respond = ( { status = 200, statusText = 'OK', body = '{}' } = {} ) => ( {
	ok: status >= 200 && status < 300,
	status,
	statusText,
	text: async () => body,
} );

/**
 * Drive a fetchJson call to completion, flushing the retry delays so the test
 * does not wait out the real backoff.
 *
 * @param {Promise} promise The pending fetchJson promise.
 * @return {Promise} Settles the same way the input promise does.
 */
async function withTimersFlushed( promise ) {
	const settled = promise.then(
		( value ) => ( { value } ),
		( error ) => ( { error } )
	);
	await vi.runAllTimersAsync();
	const result = await settled;
	if ( result.error ) {
		throw result.error;
	}
	return result.value;
}

describe( 'fetchJson', () => {
	beforeEach( () => {
		vi.useFakeTimers();
		global.fetch = vi.fn();
	} );

	afterEach( () => {
		vi.useRealTimers();
		vi.restoreAllMocks();
	} );

	it( 'returns the parsed body on a successful response', async () => {
		global.fetch.mockResolvedValue( respond( { body: '{"foo":"bar"}' } ) );

		await expect(
			withTimersFlushed( fetchJson( URL, CREDS, 'editor settings' ) )
		).resolves.toEqual( { foo: 'bar' } );
		expect( global.fetch ).toHaveBeenCalledTimes( 1 );
	} );

	it( 'retries a transient 5xx and succeeds once the endpoint recovers', async () => {
		global.fetch
			.mockResolvedValueOnce(
				respond( { status: 503, statusText: 'Service Unavailable' } )
			)
			.mockResolvedValue( respond( { body: '{"ready":true}' } ) );

		await expect(
			withTimersFlushed( fetchJson( URL, CREDS, 'editor settings' ) )
		).resolves.toEqual( { ready: true } );
		expect( global.fetch ).toHaveBeenCalledTimes( 2 );
	} );

	it( 'retries a PHP notice leaking into the body', async () => {
		global.fetch
			.mockResolvedValueOnce(
				respond( { body: '<br /><b>Warning</b>: something{}' } )
			)
			.mockResolvedValue( respond( { body: '{"ready":true}' } ) );

		await expect(
			withTimersFlushed( fetchJson( URL, CREDS, 'editor settings' ) )
		).resolves.toEqual( { ready: true } );
		expect( global.fetch ).toHaveBeenCalledTimes( 2 );
	} );

	it( 'retries a network-level rejection', async () => {
		global.fetch
			.mockRejectedValueOnce( new Error( 'ECONNREFUSED' ) )
			.mockResolvedValue( respond( { body: '{"ready":true}' } ) );

		await expect(
			withTimersFlushed( fetchJson( URL, CREDS, 'editor settings' ) )
		).resolves.toEqual( { ready: true } );
		expect( global.fetch ).toHaveBeenCalledTimes( 2 );
	} );

	it( 'fails immediately on a 401, without burning the retry budget', async () => {
		global.fetch.mockResolvedValue(
			respond( {
				status: 401,
				statusText: 'Unauthorized',
				body: '{"code":"incorrect_password"}',
			} )
		);

		await expect(
			withTimersFlushed( fetchJson( URL, CREDS, 'editor settings' ) )
		).rejects.toThrow( /Failed to fetch editor settings: HTTP 401/ );
		expect( global.fetch ).toHaveBeenCalledTimes( 1 );
	} );

	it( 'fails immediately on a 404, without burning the retry budget', async () => {
		global.fetch.mockResolvedValue(
			respond( { status: 404, statusText: 'Not Found', body: 'nope' } )
		);

		await expect(
			withTimersFlushed( fetchJson( URL, CREDS, 'editor assets' ) )
		).rejects.toThrow( /Failed to fetch editor assets: HTTP 404/ );
		expect( global.fetch ).toHaveBeenCalledTimes( 1 );
	} );

	it.each( [ 408, 429 ] )(
		'retries a %i, which can clear on its own',
		async ( status ) => {
			global.fetch
				.mockResolvedValueOnce( respond( { status } ) )
				.mockResolvedValue( respond( { body: '{"ready":true}' } ) );

			await expect(
				withTimersFlushed( fetchJson( URL, CREDS, 'editor settings' ) )
			).resolves.toEqual( { ready: true } );
			expect( global.fetch ).toHaveBeenCalledTimes( 2 );
		}
	);

	it( 'gives up after the retry budget and reports the last body snippet', async () => {
		global.fetch.mockResolvedValue(
			respond( { status: 500, statusText: 'Internal Server Error' } )
		);

		await expect(
			withTimersFlushed( fetchJson( URL, CREDS, 'editor settings' ) )
		).rejects.toThrow(
			/Failed to fetch editor settings after 15 attempts: HTTP 500/
		);
		expect( global.fetch ).toHaveBeenCalledTimes( 15 );
	} );
} );
