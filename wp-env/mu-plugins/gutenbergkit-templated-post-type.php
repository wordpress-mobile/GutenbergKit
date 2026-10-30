<?php
/**
 * Plugin Name: GutenbergKit Templated Post Type
 * Description: Registers a post type with a block template, for testing that new posts apply it.
 */

add_action( 'init', function () {
	register_post_type( 'templated_post', array(
		'labels'       => array(
			'name'          => 'Templated Posts',
			'singular_name' => 'Templated Post',
		),
		'description'  => 'For testing that new posts apply the post type template.',
		'public'       => true,
		'show_in_rest' => true,
		'rest_base'    => 'templated-posts',
		'supports'     => array( 'title', 'editor' ),
		'template'     => array(
			array( 'core/heading', array( 'content' => 'Prefilled heading from the template' ) ),
			array( 'core/paragraph', array( 'placeholder' => 'Placeholder paragraph from the template' ) ),
		),
	) );
} );
