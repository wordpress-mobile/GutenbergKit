/**
 * External dependencies
 */
import { useEffect, useRef } from 'react';

/**
 * WordPress dependencies
 */
import { createBlobURL } from '@wordpress/blob';
import { Button, Placeholder } from '@wordpress/components';
import { addFilter } from '@wordpress/hooks';

/**
 * Internal dependencies
 */
import { openPicker } from './utils';

// eslint-disable-next-line react-refresh/only-export-components
function MediaPlaceholder(props) {
	const {
		icon,
		labels,
		onDoubleClick,
		mediaPreview,
		style,
		notices,
		content,
		onSelect,
		disableMediaButtons,
		multiple = false,
		placeholder,
		value,
	} = props || {};
	let { instructions, title } = labels || {};
	const listenerRef = useRef();
	const callbackId = useRef(value?.id ?? Math.floor(Math.random() * 1001));

	useEffect(() => {
		const listenerID = `mediaUploadComplete-${callbackId.current}`;

		if (!listenerRef.current) {
			listenerRef.current = document.addEventListener(
				listenerID,
				function (event) {
					let images;

					if (event.detail?.mediaJSON) {
						const media = event.detail.mediaJSON;
						const mediaData = !multiple
							? media[0]
							: Array.isArray(media)
								? media
								: [media];

						onSelect(mediaData);
						return;
					}

					if (event.detail?.localUrl) {
						fetch(event.detail?.localUrl)
							.then((response) => response.arrayBuffer())
							.then((arrayBuffer) => {
								const blob = new Blob([arrayBuffer], {
									type: 'image/jpg',
								});
								const url = createBlobURL(blob);
								const imageData = {
									...(multiple ? { blob: url } : {}),
									...(!multiple ? { url: url } : {}),
									type: 'image',
									id: parseInt(event.detail.id, 10),
								};
								images = multiple ? [imageData] : imageData;
								onSelect(images);
							})
							.catch((error) =>
								console.error('Error fetching the file:', error)
							);
						return;
					}

					const imageData = {
						url: event.detail.url,
						type: 'image',
						id: parseInt(event.detail.id, 10),
					};
					images = multiple ? [imageData] : imageData;
					onSelect(images);
				}
			);
		}
		return () => {
			listenerRef.current?.remove();
		};
		// eslint-disable-next-line react-hooks/exhaustive-deps
	}, []);

	if (disableMediaButtons) {
		return null;
	}

	if (placeholder) {
		return placeholder(
			<>
				{content}
				<Button
					variant="primary"
					className={'block-editor-media-placeholder__button'}
					onClick={() => openPicker(callbackId.current, multiple)}
				>
					{'Add media'}
				</Button>
			</>
		);
	}

	return (
		<Placeholder
			icon={icon}
			label={title}
			instructions={instructions}
			notices={notices}
			onDoubleClick={onDoubleClick}
			preview={mediaPreview}
			style={style}
		>
			{content}
			<Button
				variant="primary"
				className={'block-editor-media-placeholder__button'}
				onClick={() => openPicker(callbackId.current, multiple)}
			>
				{'Add media'}
			</Button>
		</Placeholder>
	);
}

addFilter(
	'editor.MediaPlaceholder',
	'core/editor/components/media-placeholder',
	() => MediaPlaceholder
);
