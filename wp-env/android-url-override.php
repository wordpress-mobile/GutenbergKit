<?php
/**
 * Plugin Name: GutenbergKit Android URL Override
 * Description: Remaps WordPress site URLs from localhost/127.0.0.1 to 10.0.2.2 for Android emulator compatibility.
 */

// `site_url()`, `home_url()`, the REST index and `/wp/v2/settings` all read
// these options, so remapping them covers every URL built from the site URL.
add_filter( 'option_siteurl', 'gutenbergkit_android_remap_url' );
add_filter( 'option_home', 'gutenbergkit_android_remap_url' );

// The content and plugin URL constants are defined before mu-plugins load, so
// they keep the original host and need their own filters.
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
