<?php
/**
 * Plugin Name: GutenbergKit Jetpack Blocks
 * Description: Auto-activates the Jetpack blocks module for local GutenbergKit development.
 */

add_action( 'plugins_loaded', function () {
	if ( class_exists( 'Jetpack' ) && ! Jetpack::is_module_active( 'blocks' ) ) {
		Jetpack::activate_module( 'blocks', false, false );
	}
} );
