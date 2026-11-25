import { createHigherOrderComponent } from '@wordpress/compose';
import { createElement } from '@wordpress/element';
import { addFilter, hasFilter, removeFilter } from '@wordpress/hooks';
import VideoPressUnsupported from '../components/videopress-unsupported';
import { debug, warn } from './logger';

/**
 * Jetpack's filter that replaces each unsupported `videopress/video` block with
 * a `core/video` block on render, dropping the VideoPress-only attributes.
 */
const CONVERSION_FILTER = 'videopress/jetpack-convert-from-v6-to-v5';

/**
 * Jetpack's `core/video` VideoPress extension, present whenever Jetpack
 * VideoPress is active.
 */
const VIDEOPRESS_EXTENSION_FILTER = 'jetpack/videopress';

/**
 * Keeps `videopress/video` blocks as they are when the editor doesn't allow
 * the block type, and shows a placeholder for them.
 *
 * Without this, Jetpack converts each block to `core/video` as the post opens,
 * so an untouched post reports changes and the host saves the conversion.
 *
 * Must run before the editor's first render: `withFilters` renders once more
 * with a removed filter, which is enough to convert the block.
 *
 * @todo Remove once the `videopress/video` block type is allowed and stable.
 *
 * @return {void}
 */
export function initializeVideoPressUnsupportedBlock() {
	const removedConversion =
		removeFilter( 'editor.BlockListBlock', CONVERSION_FILTER ) > 0;

	if ( ! removedConversion ) {
		if (
			! hasFilter(
				'blocks.registerBlockType',
				VIDEOPRESS_EXTENSION_FILTER
			)
		) {
			// No Jetpack VideoPress on this site.
			return;
		}

		warn(
			`VideoPress: Jetpack's "${ CONVERSION_FILTER }" filter wasn't found. If it was renamed, VideoPress blocks may convert to Video blocks on open.`
		);
	}

	addFilter(
		'editor.BlockEdit',
		'gutenberg-kit/videopress-unsupported',
		withVideoPressUnsupportedPlaceholder
	);

	debug( 'VideoPress unsupported block placeholder initialized' );
}

/**
 * Renders the placeholder in place of the default edit UI for unsupported
 * `videopress/video` blocks.
 */
const withVideoPressUnsupportedPlaceholder = createHigherOrderComponent(
	( BlockEdit ) => ( props ) =>
		isUnsupportedVideoPressBlock( props )
			? createElement( VideoPressUnsupported, props )
			: createElement( BlockEdit, props ),
	'withVideoPressUnsupportedPlaceholder'
);

/**
 * Whether the block is a `videopress/video` block parsed as `core/missing`.
 *
 * @param {Object} props            Block edit props.
 * @param {string} props.name       Block name.
 * @param {Object} props.attributes Block attributes.
 *
 * @return {boolean} Whether the block is an unsupported VideoPress block.
 */
function isUnsupportedVideoPressBlock( { name, attributes } ) {
	return (
		name === 'core/missing' &&
		attributes?.originalName === 'videopress/video'
	);
}
