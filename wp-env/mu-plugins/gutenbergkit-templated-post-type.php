<?php
/**
 * Plugin Name: GutenbergKit Templated Post Type
 * Description: Registers a post type with a block template, for testing that new posts apply it.
 */

add_action( 'init', function () {
	register_post_type( 'gbk_templated', array(
		'label'        => 'Templated Posts',
		'public'       => true,
		'show_in_rest' => true,
		'rest_base'    => 'gbk-templated',
		'supports'     => array( 'title', 'editor' ),
		'template'     => array(
			array( 'core/heading', array( 'content' => 'Template heading' ) ),
			array( 'core/paragraph', array( 'placeholder' => 'Template paragraph' ) ),
		),
	) );
} );
