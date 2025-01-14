/**
 * WordPress dependencies
 */
import { useSelect } from '@wordpress/data';
import { useMemo } from '@wordpress/element';
import { store as coreStore } from '@wordpress/core-data';
import {
	store as editorStore,
	mediaUpload,
	privateApis as editorPrivateApis,
} from '@wordpress/editor';

/**
 * Internal dependencies
 */
import { unlock } from '../../lock-unlock';

const { useBlockEditorSettings } = unlock(editorPrivateApis);

export function useGBKitSettings(post) {
	const {
		blockPatterns,
		editorSettings,
		hasUploadPermissions,
		reusableBlocks,
	} = useSelect(
		(select) => {
			const { getEntityRecord, getEntityRecords } = select(coreStore);
			const { getEditorSettings } = select(editorStore);
			const user = getEntityRecord('root', 'user', post.author);

			return {
				editorSettings: getEditorSettings(),
				blockPatterns: select(coreStore).getBlockPatterns(),
				hasUploadPermissions: user?.capabilities?.upload_files ?? true,
				reusableBlocks: getEntityRecords('postType', 'wp_block'),
			};
		},
		[post.author]
	);

	const blockEditorSettings = useBlockEditorSettings(
		editorSettings,
		post.type,
		post.id,
		'visual'
	);

	const settings = useMemo(
		() => ({
			...blockEditorSettings,
			hasFixedToolbar: true,
			mediaUpload: hasUploadPermissions ? mediaUpload : undefined,
			__experimentalReusableBlocks: reusableBlocks,
			__experimentalBlockPatterns: blockPatterns,
		}),
		[
			blockEditorSettings,
			blockPatterns,
			hasUploadPermissions,
			reusableBlocks,
		]
	);

	return settings;
}
