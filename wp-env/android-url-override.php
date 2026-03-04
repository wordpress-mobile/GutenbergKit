<?php
/**
 * Plugin Name: GutenbergKit Android URL Override
 * Description: Remaps WordPress site URLs from localhost/127.0.0.1 to 10.0.2.2 for Android emulator compatibility.
 */

add_filter( 'site_url', 'gutenbergkit_android_remap_url' );
add_filter( 'home_url', 'gutenbergkit_android_remap_url' );
add_filter( 'content_url', 'gutenbergkit_android_remap_url' );
add_filter( 'plugins_url', 'gutenbergkit_android_remap_url' );

add_filter( 'upload_dir', function ( $uploads ) {
	$uploads['url']     = gutenbergkit_android_remap_url( $uploads['url'] );
	$uploads['baseurl'] = gutenbergkit_android_remap_url( $uploads['baseurl'] );
	return $uploads;
} );

function gutenbergkit_android_remap_url( $url ) {
	return str_replace(
		array( '://localhost', '://127.0.0.1' ),
		'://10.0.2.2',
		$url
	);
}
