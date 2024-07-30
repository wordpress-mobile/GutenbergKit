/* eslint-disable react/prop-types */

/**
 * External dependencies
 */
import { useEffect, useRef } from 'react';

/**
 * WordPress dependencies
 */
import { addFilter } from '@wordpress/hooks';
import {
	Dropdown,
	MenuItem,
	ToolbarButton,
	NavigableMenu,
} from '@wordpress/components';
import { __experimentalLinkControl as LinkControl } from '@wordpress/block-editor';

/**
 * Internal dependencies
 */
import { openPicker } from './utils';

// eslint-disable-next-line react-refresh/only-export-components
function MediaReplaceFlow(props) {
	const {
		mediaURL,
		onSelect,
		onSelectURL,
		name = 'Replace',
		children,
		multiple = false,
		popoverProps,
	} = props;
	const editMediaButtonRef = useRef();
	const listenerRef = useRef();
	const callbackId = useRef(Math.floor(Math.random() * 1001));
	const onCloseRef = useRef();

	const selectMedia = (media) => {
		onCloseRef?.current?.();
		// Calling `onSelect` after the state update since it might unmount the component.
		const selectedMedia = multiple ? media : media[0];
		onSelect(selectedMedia);
	};

	useEffect(() => {
		if (!listenerRef.current) {
			listenerRef.current = document.addEventListener(
				`mediaUploadComplete-${callbackId.current}`,
				function (event) {
					const media = event.detail.mediaJSON;
					selectMedia(media);
					// Perform actions with imageURL
				}
			);
		}
		// eslint-disable-next-line react-hooks/exhaustive-deps
	}, []);

	return (
		<Dropdown
			popoverProps={popoverProps}
			contentClassName="block-editor-media-replace-flow__options"
			renderToggle={({ isOpen, onToggle }) => (
				<ToolbarButton
					ref={editMediaButtonRef}
					aria-expanded={isOpen}
					aria-haspopup="true"
					onClick={onToggle}
				>
					{name}
				</ToolbarButton>
			)}
			renderContent={({ onClose }) => (
				<>
					<NavigableMenu className="block-editor-media-replace-flow__media-upload-menu">
						<MenuItem
							onClick={() => {
								onCloseRef.current = onClose;
								openPicker(callbackId.current);
							}}
						>
							{'Select Media'}
						</MenuItem>
						{children}
					</NavigableMenu>
					{onSelectURL && (
						<form className={'block-editor-media-flow__url-input'}>
							<span className="block-editor-media-replace-flow__image-url-label">
								{'Current media URL:'}
							</span>

							<LinkControl
								value={{ url: mediaURL }}
								settings={[]}
								showSuggestions={false}
								onChange={({ url }) => {
									onSelectURL(url);
									editMediaButtonRef.current.focus();
								}}
							/>
						</form>
					)}
				</>
			)}
		/>
	);
}

addFilter(
	'editor.MediaReplaceFlow',
	'core/editor/components/media-replace-flow',
	() => MediaReplaceFlow
);
