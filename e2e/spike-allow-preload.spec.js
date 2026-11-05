/**
 * Spike S6 follow-up: does the site entity's update permission survive when
 * `Allow` is hidden cross-origin, as on `public-api.wordpress.com`?
 *
 * Throwaway spec. wp-env exposes `Allow`; the route below hides it again.
 * Cases:
 * - `strips`: the hosts' preload today (OPTIONS without `Allow`).
 * - `keeps`: the OPTIONS preload keeps `Allow`.
 * - `keeps-get`: also preloads `GET /wp/v2/settings` with `Allow`.
 */
/* eslint-disable playwright/expect-expect */
import fs from 'node:fs';
import path from 'node:path';
import { test } from '@playwright/test';
import EditorPage from './editor-page';
import { credentials } from './wp-env-fixtures';

const OUT = path.resolve( import.meta.dirname, '../build/s6/allow' );

async function rest( method, route ) {
	const response = await fetch( `${ credentials.siteApiRoot }${ route }`, {
		method,
		headers: { Authorization: credentials.authHeader },
	} );
	return {
		body: await response.json(),
		allow: response.headers.get( 'allow' ),
	};
}

for ( const name of [ 'strips', 'keeps', 'keeps-get' ] ) {
	test( `settings permission: ${ name }`, async ( { page } ) => {
		// Hide `Allow` from the page, as `public-api` does.
		await page.route( `${ credentials.siteApiRoot }**`, async ( route ) => {
			const response = await route.fetch();
			const headers = { ...response.headers() };
			headers[ 'access-control-expose-headers' ] =
				'X-WP-Total, X-WP-TotalPages, Link';
			await route.fulfill( { response, headers } );
		} );

		const options = await rest( 'OPTIONS', 'wp/v2/settings' );
		const settings = await rest( 'GET', 'wp/v2/settings' );
		const types = await rest( 'GET', 'wp/v2/types?context=view' );
		const allow = name === 'strips' ? {} : { Allow: options.allow };
		const preloadData = {
			'/wp/v2/types?context=view': { body: types.body },
			...( name === 'keeps-get' && {
				'/wp/v2/settings': { body: settings.body, headers: allow },
			} ),
			OPTIONS: {
				'/wp/v2/settings': { body: options.body, headers: allow },
			},
		};

		// Record every change to the permission from page load on.
		await page.addInitScript( () => {
			window.permissionLog = [];
			const timer = setInterval( () => {
				const data = window.wp?.data;
				if ( ! data?.select( 'core' ) ) {
					return;
				}
				clearInterval( timer );
				let last;
				data.subscribe( () => {
					const value = data
						.select( 'core' )
						.canUser( 'update', { kind: 'root', name: 'site' } );
					if ( value !== last ) {
						last = value;
						window.permissionLog.push( String( value ) );
					}
				} );
			}, 5 );
		} );

		const editor = new EditorPage( page );
		await editor.setup( { preloadData } );
		const result = await page.evaluate( async () => {
			const { resolveSelect, select } = window.wp.data;
			await resolveSelect( 'core' ).getEntityRecord( 'root', 'site' );
			return {
				final: select( 'core' ).canUser( 'update', {
					kind: 'root',
					name: 'site',
				} ),
				timeline: window.permissionLog,
			};
		} );
		await page.unrouteAll( { behavior: 'ignoreErrors' } );
		fs.mkdirSync( OUT, { recursive: true } );
		fs.writeFileSync(
			path.join( OUT, `${ name }.json` ),
			JSON.stringify( { serverAllow: options.allow, ...result }, null, 2 )
		);
	} );
}
