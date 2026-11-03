<?php
/**
 * Plugin Name: GutenbergKit Post Write Failure Simulator
 * Description: Fails, delays or cuts off REST writes to posts so the editor's save outcome handling can be exercised locally. Development only.
 *
 * Modes:
 *
 *   error500  Reject every post write with a 500 before anything is written.
 *   slow90s   Wait 90 seconds, then apply the write and answer normally.
 *   drop      Apply the write, then cut the connection before the response
 *             body is complete, so the client never learns the result.
 *   conflict  Act as another writer: when the mode is set with `post=<id>`,
 *             bump that post's modified date at once (and, unless `content=0`,
 *             append to its content). Writes then pass through unchanged.
 *   off       Normal writes (the default).
 *
 * "Post writes" are POST/PUT/PATCH requests handled by a posts controller
 * (any post type, not attachments) or an autosaves controller. The mode is an
 * option rather than a request flag, because on iOS the save is relayed by
 * URLSession, which a page can't add test-only parameters to.
 *
 *   curl -u "$USER:$APP_PASSWORD" -X POST \
 *     'http://localhost:8888/wp-json/gutenbergkit/v1/post-write-failure?mode=drop'
 *
 * Or with WP-CLI:
 *
 *   npx wp-env run cli wp option update gbk_post_write_failure_mode drop
 */

const GBK_POST_WRITE_FAILURE_OPTION = 'gbk_post_write_failure_mode';
const GBK_POST_WRITE_FAILURE_MODES  = array( 'off', 'error500', 'slow90s', 'drop', 'conflict' );

/**
 * Registers a route for reading and setting the mode without WP-CLI.
 */
function gbk_post_write_failure_register_route() {
	register_rest_route(
		'gutenbergkit/v1',
		'/post-write-failure',
		array(
			'methods'             => array( 'GET', 'POST' ),
			'permission_callback' => function () {
				return current_user_can( 'manage_options' );
			},
			'args'                => array(
				'mode'    => array(
					'type'    => 'string',
					'enum'    => GBK_POST_WRITE_FAILURE_MODES,
					'default' => null,
				),
				'post'    => array(
					'type'    => 'integer',
					'default' => 0,
				),
				'content' => array(
					'type'    => 'boolean',
					'default' => true,
				),
			),
			'callback'            => 'gbk_post_write_failure_handle_mode_request',
		)
	);
}
add_action( 'rest_api_init', 'gbk_post_write_failure_register_route' );

/**
 * Reports the mode, setting it first when the request names one.
 *
 * @param WP_REST_Request $request The request.
 */
function gbk_post_write_failure_handle_mode_request( $request ) {
	$mode   = $request->get_param( 'mode' );
	$result = array();

	if ( null !== $mode ) {
		update_option( GBK_POST_WRITE_FAILURE_OPTION, $mode );

		$post_id = (int) $request->get_param( 'post' );
		if ( 'conflict' === $mode && $post_id ) {
			$result['concurrentEdit'] = gbk_post_write_failure_concurrent_edit(
				$post_id,
				(bool) $request->get_param( 'content' )
			);
		}
	}

	$result['mode'] = gbk_post_write_failure_mode();

	return $result;
}

/**
 * Returns the active mode.
 */
function gbk_post_write_failure_mode() {
	$mode = get_option( GBK_POST_WRITE_FAILURE_OPTION, 'off' );

	return in_array( $mode, GBK_POST_WRITE_FAILURE_MODES, true ) ? $mode : 'off';
}

/**
 * Simulates another writer saving the post.
 *
 * Writes the row directly rather than through `wp_update_post()`, so no
 * revision or hook makes the edit look like the editor's own.
 *
 * @param int  $post_id      The post.
 * @param bool $edit_content Whether to change the content too, or only the
 *                           modified date (a conflict check must not abort for
 *                           that one).
 * @return array|WP_Error The post's new modified date and whether its content
 *                        changed.
 */
function gbk_post_write_failure_concurrent_edit( $post_id, $edit_content ) {
	global $wpdb;

	$post = get_post( $post_id );
	if ( ! $post ) {
		return new WP_Error( 'gbk_no_post', 'No such post.', array( 'status' => 404 ) );
	}

	// One minute ahead, so the bump is visible even when it lands in the same
	// second as the editor's last save.
	$gmt   = gmdate( 'Y-m-d H:i:s', time() + 60 );
	$local = get_date_from_gmt( $gmt );
	$data  = array(
		'post_modified'     => $local,
		'post_modified_gmt' => $gmt,
	);

	if ( $edit_content ) {
		$data['post_content'] = $post->post_content . "\n\n<!-- wp:paragraph -->\n<p>Concurrent edit at {$gmt} GMT</p>\n<!-- /wp:paragraph -->";
	}

	$wpdb->update( $wpdb->posts, $data, array( 'ID' => $post_id ) );
	clean_post_cache( $post_id );

	return array(
		'post'          => $post_id,
		'modifiedGmt'   => str_replace( ' ', 'T', $gmt ),
		'contentEdited' => $edit_content,
	);
}

/**
 * Whether a REST request is a write handled by a posts or autosaves controller.
 *
 * WordPress has already applied any `X-HTTP-Method-Override` or `_method` by
 * the time the request object exists, so its method is the effective one.
 *
 * @param WP_REST_Request $request The request.
 * @param array           $handler The matched route handler.
 */
function gbk_post_write_failure_is_post_write( $request, $handler ) {
	if ( ! in_array( $request->get_method(), array( 'POST', 'PUT', 'PATCH' ), true ) ) {
		return false;
	}

	$controller = is_array( $handler['callback'] ?? null ) ? $handler['callback'][0] : null;

	if ( $controller instanceof WP_REST_Attachments_Controller ) {
		return false;
	}

	return $controller instanceof WP_REST_Posts_Controller
		|| $controller instanceof WP_REST_Autosaves_Controller;
}

/**
 * Fails or delays a post write before it is applied.
 *
 * @param mixed           $response Result so far; null to run the callback.
 * @param array           $handler  The matched route handler.
 * @param WP_REST_Request $request  The request.
 */
function gbk_post_write_failure_before_callbacks( $response, $handler, $request ) {
	if ( null !== $response || ! gbk_post_write_failure_is_post_write( $request, $handler ) ) {
		return $response;
	}

	switch ( gbk_post_write_failure_mode() ) {
		case 'error500':
			return new WP_Error(
				'gbk_simulated_post_write_failure',
				'GutenbergKit simulated a server error. Nothing was written.',
				array( 'status' => 500 )
			);

		case 'slow90s':
			// Playground runs several PHP workers (`--experimental-multi-worker`),
			// so other requests are still answered while this one waits.
			set_time_limit( 0 );
			sleep( 90 );
			return $response;
	}

	return $response;
}
add_filter( 'rest_request_before_callbacks', 'gbk_post_write_failure_before_callbacks', 10, 3 );

/**
 * Cuts the connection after a post write has been applied.
 *
 * Sends the status line and CORS headers, then a body shorter than the
 * declared `Content-Length`, and exits. The write is committed, but the client
 * sees the transfer fail, as it would if the network dropped mid-response.
 *
 * @param mixed           $response The callback's result.
 * @param array           $handler  The matched route handler.
 * @param WP_REST_Request $request  The request.
 */
function gbk_post_write_failure_after_callbacks( $response, $handler, $request ) {
	if ( 'drop' !== gbk_post_write_failure_mode()
		|| is_wp_error( $response )
		|| ! gbk_post_write_failure_is_post_write( $request, $handler ) ) {
		return $response;
	}

	// The CORS headers normally go out in `rest_pre_serve_request`, which this
	// exit skips. Without them a cross-origin caller sees a CORS error, which
	// also reads as a network failure, but would hide which one happened.
	if ( function_exists( 'gutenbergkit_cors_send_origin_headers' ) ) {
		gutenbergkit_cors_send_origin_headers( get_http_origin() );
	} else {
		rest_send_cors_headers( null );
	}

	status_header( 200 );
	header( 'Content-Type: application/json; charset=UTF-8' );
	header( 'Content-Length: 100000' );
	echo '{"id":';
	flush();
	exit;
}
add_filter( 'rest_request_after_callbacks', 'gbk_post_write_failure_after_callbacks', 10, 3 );
