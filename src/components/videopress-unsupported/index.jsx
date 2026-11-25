import { useBlockProps } from '@wordpress/block-editor';
import { parse } from '@wordpress/block-serialization-default-parser';
import { SandBox, Spinner } from '@wordpress/components';
import { store as coreStore } from '@wordpress/core-data';
import { useSelect } from '@wordpress/data';
import { useMemo } from '@wordpress/element';
import { __, sprintf } from '@wordpress/i18n';
import { Icon, info } from '@wordpress/icons';
import './style.scss';

/**
 * Placeholder for a `videopress/video` block the editor doesn't allow.
 *
 * Shows a non-interactive preview of the video and explains that its settings
 * can't be edited. The block keeps its original markup.
 *
 * @param {Object} props            Block edit props.
 * @param {Object} props.attributes `core/missing` attributes, including the
 *                                  block's original markup.
 *
 * @return {Element} The placeholder.
 */
export default function VideoPressUnsupported( { attributes } ) {
	const blockProps = useBlockProps( {
		className: 'gutenberg-kit-videopress-unsupported',
	} );
	const guid = useMemo(
		() => getGuid( attributes.originalContent ),
		[ attributes.originalContent ]
	);
	const url = guid ? `https://videopress.com/v/${ guid }` : undefined;

	// Core-data fetches `/oembed/1.0/proxy` and caches the result, so moving
	// the block or remounting it doesn't fetch again. A failed fetch is `false`.
	const preview = useSelect(
		( select ) =>
			url ? select( coreStore ).getEmbedPreview( url ) : false,
		[ url ]
	);
	const isLoading = preview === undefined;

	return (
		<figure { ...blockProps }>
			{ preview?.html ? (
				// Like core embeds, size the preview by the video's aspect ratio
				// rather than its content height, which can exceed the player.
				<div
					className="gutenberg-kit-videopress-unsupported__preview"
					style={ { aspectRatio: getAspectRatio( preview ) } }
				>
					<SandBox
						allowSameOrigin
						html={ preview.html }
						scripts={ preview.scripts }
						title={ sprintf(
							// translators: %s: host providing embed content e.g: www.youtube.com
							__( 'Embedded content from %s' ),
							'videopress.com'
						) }
						type="wp-has-aspect-ratio"
					/>
				</div>
			) : (
				<div className="gutenberg-kit-videopress-unsupported__placeholder">
					{ isLoading && <Spinner /> }
				</div>
			) }
			<figcaption className="gutenberg-kit-videopress-unsupported__notice">
				<Icon icon={ info } size={ 20 } />
				<span>
					{ __(
						'Editing VideoPress settings is not yet supported in the app. To make changes, edit the post on the web.',
						'gutenberg-kit'
					) }
				</span>
			</figcaption>
		</figure>
	);
}

/**
 * Reads the VideoPress guid from the block's original markup.
 *
 * @param {string} [originalContent] The block's original markup.
 *
 * @return {string|undefined} The guid, if valid.
 */
function getGuid( originalContent ) {
	const [ block ] = parse( originalContent ?? '' );
	const guid = block?.attrs?.guid;

	// Guids are alphanumeric; anything else would alter the embed URL.
	return typeof guid === 'string' && /^[a-z0-9]+$/i.test( guid )
		? guid
		: undefined;
}

/**
 * Returns the CSS aspect ratio of an oEmbed preview.
 *
 * @param {Object} preview        oEmbed response.
 * @param {number} preview.width  Embed width.
 * @param {number} preview.height Embed height.
 *
 * @return {string} The aspect ratio, 16:9 when the size is unknown.
 */
function getAspectRatio( { width, height } ) {
	return width > 0 && height > 0 ? `${ width } / ${ height }` : '16 / 9';
}
