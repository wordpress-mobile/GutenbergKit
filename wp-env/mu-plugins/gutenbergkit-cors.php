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

add_action( 'rest_api_init', function () {
	// Remove default WordPress CORS headers to avoid duplicates.
	remove_filter( 'rest_pre_serve_request', 'rest_send_cors_headers' );

	add_filter( 'rest_pre_serve_request', function ( $served ) {
		gutenbergkit_cors_send_origin_headers( get_http_origin() );
		return $served;
	});
}, 15 );

// Handle preflight OPTIONS requests early.
add_action( 'init', function () {
	if ( isset( $_SERVER['REQUEST_METHOD'] ) && 'OPTIONS' === $_SERVER['REQUEST_METHOD'] ) {
		gutenbergkit_cors_send_origin_headers( get_http_origin() );
		header( 'Access-Control-Max-Age: 86400' );
		status_header( 204 );
		exit;
	}
});
