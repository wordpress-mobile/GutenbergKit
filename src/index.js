/**
 * External dependencies
 */
import jquery from 'jquery';

/**
 * Internal dependencies
 */
import { initializeBundledEditor } from './utils/bundled-editor';
import './index.scss';

window.jQuery = jquery; // Expose jQuery for plugins
initializeBundledEditor();
