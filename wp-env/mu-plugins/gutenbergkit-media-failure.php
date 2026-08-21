<?php
/**
 * Plugin Name: GutenbergKit Media Failure Simulator
 * Description: Fatals during image sub-size generation so the editor's media upload post-process retry can be exercised locally. Development only.
 *
 * Reproduces the failure the retry recovers from: WordPress creates the
 * attachment row and sends `X-WP-Upload-Attachment-ID`, then
 * `wp_generate_attachment_metadata()` fatals — typically a PHP `memory_limit`
 * or `max_execution_time` fatal on a large image. The editor reads that header
 * off the 5xx and retries `POST /wp/v2/media/<id>/post-process`.
 *
 * Adapted from https://github.com/WordPress/gutenberg/pull/17858#issuecomment-540114688,
 * with the random failure rate replaced by an explicit mode so both outcomes
 * are reproducible:
 *
 *   recover  Fail once per attachment, then succeed. The retry recovers the
 *            upload and the attachment completes.
 *   always   Fail every time. Exhausts all five retries, after which the editor
 *            DELETEs the orphaned attachment.
 *   off      Normal uploads (the default).
 *
 * The mode is stored as an option rather than read per-request, because the
 * upload and each post-process retry are separate requests — and an upload
 * routed through the native upload server is relayed by URLSession/OkHttp,
 * which carries no browser cookie. Set it over the REST API:
 *
 *   curl -u "$USER:$APP_PASSWORD" -X POST \
 *     'http://localhost:8888/wp-json/gutenbergkit/v1/media-failure?mode=recover'
 *
 * Or with WP-CLI:
 *
 *   npx wp-env run cli wp option update gbk_media_failure_mode recover
 */

const GBK_MEDIA_FAILURE_OPTION = 'gbk_media_failure_mode';
const GBK_MEDIA_FAILURE_MODES  = array( 'off', 'recover', 'always' );

/**
 * Registers a route for flipping the failure mode without WP-CLI.
 */
function gbk_media_failure_register_route() {
	register_rest_route(
		'gutenbergkit/v1',
		'/media-failure',
		array(
			'methods'             => array( 'GET', 'POST' ),
			'permission_callback' => function () {
				return current_user_can( 'manage_options' );
			},
			'args'                => array(
				'mode' => array(
					'type'    => 'string',
					'enum'    => GBK_MEDIA_FAILURE_MODES,
					'default' => null,
				),
			),
			'callback'            => function ( $request ) {
				$mode = $request->get_param( 'mode' );

				if ( null !== $mode ) {
					update_option( GBK_MEDIA_FAILURE_OPTION, $mode );
					// A stale per-attachment counter would make `recover` skip
					// its failure on an attachment that already burned one.
					gbk_media_failure_reset_counters();
				}

				return array( 'mode' => gbk_media_failure_mode() );
			},
		)
	);
}
add_action( 'rest_api_init', 'gbk_media_failure_register_route' );

/**
 * Clears the per-attachment failure counters.
 */
function gbk_media_failure_reset_counters() {
	global $wpdb;
	$wpdb->delete( $wpdb->postmeta, array( 'meta_key' => '_gbk_media_failure_count' ) );
}

/**
 * Returns the active failure mode.
 */
function gbk_media_failure_mode() {
	$mode = get_option( GBK_MEDIA_FAILURE_OPTION, 'off' );

	return in_array( $mode, GBK_MEDIA_FAILURE_MODES, true ) ? $mode : 'off';
}

/**
 * Whether this sub-size generation pass should fatal.
 *
 * In `recover` mode the count is tracked per attachment, so a second upload
 * fails once too rather than succeeding immediately because an earlier upload
 * already burned the failure.
 *
 * @param int $attachment_id The attachment being processed.
 */
function gbk_media_failure_should_fail( $attachment_id ) {
	switch ( gbk_media_failure_mode() ) {
		case 'always':
			return true;

		case 'recover':
			$key = '_gbk_media_failure_count';
			// `get_post_meta` returns '' when unset, which casts to 0.
			$attempts = (int) get_post_meta( $attachment_id, $key, true );
			update_post_meta( $attachment_id, $key, $attempts + 1 );
			return 0 === $attempts;

		default:
			return false;
	}
}

/**
 * Whether the current request is one this simulator should be able to fail.
 *
 * Only the upload and its `post-process` retries. A `DELETE` must be left alone
 * even in `always` mode: core's `force=true` delete path also runs sub-size
 * handling, so failing there fatals the editor's orphan cleanup — the very
 * request that proves the retry gave up correctly. Worse, a fatal aborts the
 * request before `rest_pre_serve_request` adds CORS headers, so the editor sees
 * a CORS error rather than the 500, which reads like a bug in the editor rather
 * than in this plugin.
 */
function gbk_media_failure_is_failable_request() {
	$method = isset( $_SERVER['REQUEST_METHOD'] )
		? strtoupper( sanitize_text_field( wp_unslash( $_SERVER['REQUEST_METHOD'] ) ) )
		: '';

	// api-fetch tunnels DELETE through POST with an override header, so the
	// bare method is not enough to identify a delete.
	$override = isset( $_SERVER['HTTP_X_HTTP_METHOD_OVERRIDE'] )
		? strtoupper( sanitize_text_field( wp_unslash( $_SERVER['HTTP_X_HTTP_METHOD_OVERRIDE'] ) ) )
		: '';

	return 'DELETE' !== $method && 'DELETE' !== $override;
}

/**
 * Fatals during sub-size generation when the active mode calls for it.
 *
 * Hooks both filters core runs while building sub-sizes: the initial upload
 * goes through `intermediate_image_sizes_advanced`, and the `post-process`
 * retry goes through `wp_get_missing_image_subsizes`.
 *
 * @param array $sizes         The sizes to generate.
 * @param mixed $metadata      Image metadata (unused).
 * @param int   $attachment_id The attachment being processed.
 */
function gbk_media_failure_maybe_fail( $sizes, $metadata = null, $attachment_id = 0 ) {
	if ( ! gbk_media_failure_is_failable_request() ) {
		return $sizes;
	}

	if ( gbk_media_failure_should_fail( $attachment_id ) ) {
		// Send the 500 explicitly before dying. A real PHP fatal under FPM
		// surfaces as a 500, but the Playground runtime wp-env uses returns 200,
		// which the editor's retry (`status >= 500`) would ignore. The status
		// has to be set here because `X-WP-Upload-Attachment-ID` was already
		// sent above this filter, so PHP has committed the response.
		if ( ! headers_sent() ) {
			http_response_code( 500 );
		}

		// Terminate the way a memory_limit or max_execution_time fatal does,
		// after the attachment row exists and its ID header has been sent.
		trigger_error( 'GutenbergKit simulated media failure', E_USER_ERROR );
		exit;
	}

	return $sizes;
}
add_filter( 'intermediate_image_sizes_advanced', 'gbk_media_failure_maybe_fail', 10, 3 );
add_filter( 'wp_get_missing_image_subsizes', 'gbk_media_failure_maybe_fail', 10, 3 );
