import { useBlockProps } from '@wordpress/block-editor';
import { parse } from '@wordpress/block-serialization-default-parser';
import { Notice, SandBox, Spinner } from '@wordpress/components';
import { store as coreStore } from '@wordpress/core-data';
import { useSelect } from '@wordpress/data';
import { useMemo } from '@wordpress/element';
import { __, sprintf } from '@wordpress/i18n';
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
				<div className="gutenberg-kit-videopress-unsupported__preview">
					<SandBox
						allowSameOrigin
						html={ preview.html }
						scripts={ preview.scripts }
						title={ sprintf(
							// translators: %s: host providing embed content e.g: www.youtube.com
							__( 'Embedded content from %s' ),
							'videopress.com'
						) }
						type="video"
					/>
				</div>
			) : (
				<div className="gutenberg-kit-videopress-unsupported__placeholder">
					{ isLoading && <Spinner /> }
				</div>
			) }
			<Notice status="info" isDismissible={ false }>
				{ __(
					"VideoPress video settings can't be edited in the app yet. This video is kept as is. To change its settings, edit the post on the web.",
					'gutenberg-kit'
				) }
			</Notice>
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
