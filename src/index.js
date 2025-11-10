/**
 * External dependencies
 */
import jquery from 'jquery';

/**
 * Internal dependencies
 */
import { setUpEditorEnvironment } from './utils/editor-environment';
import './index.scss';

window.jQuery = jquery; // Expose jQuery for plugins
setUpEditorEnvironment();
