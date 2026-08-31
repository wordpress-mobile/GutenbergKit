<?php
/**
 * Plugin Name: GutenbergKit CORS
 * Description: Adds CORS headers to WordPress REST API responses for local GutenbergKit development.
 */

/**
 * Returns the list of origins allowed to make cross-origin requests.
 */
function gutenbergkit_cors_allowed_origins() {
	return array(
		'http://localhost:5173',                    // Vite dev server
		'http://localhost:4173',                    // Vite preview server
		'http://10.0.2.2:5173',                    // Vite dev server (Android emulator)
		'http://10.0.2.2:4173',                    // Vite preview server (Android emulator)
		'https://appassets.androidplatform.net',   // Android production build (HTTPS site)
		'http://appassets.androidplatform.net',    // Android production build (HTTP site)
	);
}

/**
 * Sends CORS headers for the given origin.
 */
function gutenbergkit_cors_send_origin_headers( $origin ) {
	$allowed_origins = gutenbergkit_cors_allowed_origins();

	if ( in_array( $origin, $allowed_origins, true ) ) {
		header( 'Access-Control-Allow-Origin: ' . $origin );
		header( 'Access-Control-Allow-Credentials: true' );
	} elseif ( empty( $origin ) ) {
		// Allow requests with no Origin header (native WebViews).
		header( 'Access-Control-Allow-Origin: *' );
	}

	header( 'Access-Control-Allow-Methods: GET, POST, PUT, PATCH, DELETE, OPTIONS' );
	header( 'Access-Control-Allow-Headers: Authorization, Content-Type, X-WP-Nonce' );
}

/**
 * Exposes the `Allow` header to cross-origin callers.
 *
 * `canUser` issues `OPTIONS /wp/v2/{resource}` and reads `Allow` to decide
 * whether the user may create a page, update settings, upload media, or edit
 * global styles. Core sets that header from the matched route's permission
 * callbacks, but as of 6.8.3 exposes only `X-WP-Total`, `X-WP-TotalPages` and
 * `Link` — so cross-origin the header is on the wire and invisible to
 * JavaScript, and every capability reads as false with no error surfaced.
 *
 * Added through core's filter rather than by sending the header directly:
 * core sends its own `Access-Control-Expose-Headers`, so a second `header()`
 * call would replace that value rather than extend it.
 *
 * @see https://github.com/WordPress/wordpress-develop/blob/6.8.3/src/wp-includes/rest-api/class-wp-rest-server.php#L395-L408
 */
add_filter( 'rest_exposed_cors_headers', function ( $headers ) {
	$headers[] = 'Allow';
	return $headers;
} );

add_action( 'rest_api_init', function () {
	// Remove default WordPress CORS headers to avoid duplicates.
	remove_filter( 'rest_pre_serve_request', 'rest_send_cors_headers' );

	add_filter( 'rest_pre_serve_request', function ( $served ) {
		gutenbergkit_cors_send_origin_headers( get_http_origin() );
		return $served;
	});
}, 15 );

// Answer CORS preflights early, before WordPress routes the request.
//
// This runs site-wide rather than on `rest_api_init` because the editor also
// sends an authenticated request to `admin-ajax.php`, which core does not
// answer preflights for.
//
// Only a genuine preflight is answered here. A preflight always carries
// `Access-Control-Request-Method`; an `OPTIONS` a client sent on its own behalf
// never does, and core answers those itself — `rest_handle_options_request`
// builds the response and `rest_send_allow_header` sets `Allow` from the
// matched route's permission callbacks. Short-circuiting both made every
// `canUser` check report that the user could do nothing, with no error
// surfaced, because the request "succeeded".
//
// @see https://github.com/WordPress/wordpress-develop/blob/6.8.3/src/wp-includes/rest-api.php#L252-L256
add_action( 'init', function () {
	if ( ! isset( $_SERVER['REQUEST_METHOD'] ) || 'OPTIONS' !== $_SERVER['REQUEST_METHOD'] ) {
		return;
	}

	if ( ! isset( $_SERVER['HTTP_ACCESS_CONTROL_REQUEST_METHOD'] ) ) {
		return;
	}

	gutenbergkit_cors_send_origin_headers( get_http_origin() );
	header( 'Access-Control-Max-Age: 86400' );
	status_header( 204 );
	exit;
});
