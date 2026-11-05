<?php
/**
 * Plugin Name: GutenbergKit LAN URL Override (CMM-2752, temporary)
 * Description: When a request arrives on the Mac's LAN address, emit that address instead of 127.0.0.1/localhost, so a physical phone on Wi-Fi can load what WordPress links to. Requests to localhost are untouched.
 */

function gutenbergkit_lan_host() {
	$host = $_SERVER['HTTP_HOST'] ?? '';
	return preg_match( '/^192\.168\.\d+\.\d+(:\d+)?$/', $host ) ? $host : null;
}

function gutenbergkit_lan_remap_url( $url ) {
	$host = gutenbergkit_lan_host();
	if ( ! $host || ! is_string( $url ) ) {
		return $url;
	}
	return preg_replace( '#://(127\.0\.0\.1|localhost)(:\d+)?#', '://' . $host, $url );
}

foreach ( array( 'site_url', 'home_url', 'content_url', 'plugins_url', 'includes_url', 'rest_url', 'script_loader_src', 'style_loader_src' ) as $gutenbergkit_lan_filter ) {
	add_filter( $gutenbergkit_lan_filter, 'gutenbergkit_lan_remap_url' );
}

add_filter(
	'upload_dir',
	function ( $uploads ) {
		$uploads['url']     = gutenbergkit_lan_remap_url( $uploads['url'] );
		$uploads['baseurl'] = gutenbergkit_lan_remap_url( $uploads['baseurl'] );
		return $uploads;
	}
);
