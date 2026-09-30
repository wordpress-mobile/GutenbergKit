import React from 'react';
import ReactDOM from 'react-dom';
import moment from 'moment';
import lodash from 'lodash';
import * as ReactJSXRuntime from 'react/jsx-runtime';
import jquery from 'jquery';
import * as a11y from '@wordpress/a11y';
import * as apiFetch from '@wordpress/api-fetch';
import * as autop from '@wordpress/autop';
import * as blob from '@wordpress/blob';
import * as blockEditor from '@wordpress/block-editor';
import * as blockLibrary from '@wordpress/block-library';
import * as blockSerializationDefaultParser from '@wordpress/block-serialization-default-parser';
import * as blocks from '@wordpress/blocks';
import * as commands from '@wordpress/commands';
import * as components from '@wordpress/components';
import * as compose from '@wordpress/compose';
import * as coreData from '@wordpress/core-data';
import * as data from '@wordpress/data';
import * as dataControls from '@wordpress/data-controls';
import * as date from '@wordpress/date';
import * as deprecated from '@wordpress/deprecated';
import * as dom from '@wordpress/dom';
import * as domReady from '@wordpress/dom-ready';
import * as editPost from '@wordpress/edit-post';
import * as editor from '@wordpress/editor';
import * as element from '@wordpress/element';
import * as escapeHtml from '@wordpress/escape-html';
import * as formatLibrary from '@wordpress/format-library';
import * as globalStylesEngine from '@wordpress/global-styles-engine';
import * as htmlEntities from '@wordpress/html-entities';
import * as icons from '@wordpress/icons';
import * as isShallowEqual from '@wordpress/is-shallow-equal';
import * as keycodes from '@wordpress/keycodes';
import * as keyboardShortcuts from '@wordpress/keyboard-shortcuts';
import * as mediaUtils from '@wordpress/media-utils';
import * as notices from '@wordpress/notices';
import * as patterns from '@wordpress/patterns';
import * as plugins from '@wordpress/plugins';
import * as preferences from '@wordpress/preferences';
import * as preferencesPersistence from '@wordpress/preferences-persistence';
import * as primitives from '@wordpress/primitives';
import * as privateApis from '@wordpress/private-apis';
import * as priorityQueue from '@wordpress/priority-queue';
import * as reduxRoutine from '@wordpress/redux-routine';
import * as richText from '@wordpress/rich-text';
import * as router from '@wordpress/router';
import * as serverSideRender from '@wordpress/server-side-render';
import * as shortcode from '@wordpress/shortcode';
import * as styleEngine from '@wordpress/style-engine';
import * as sync from '@wordpress/sync';
import * as theme from '@wordpress/theme';
import * as tokenList from '@wordpress/token-list';
import * as uploadMedia from '@wordpress/upload-media';
import * as url from '@wordpress/url';
import * as viewport from '@wordpress/viewport';
import * as warning from '@wordpress/warning';
import * as widgets from '@wordpress/widgets';
import * as wordcount from '@wordpress/wordcount';
import { toCommonJS } from './to-common-js';

/**
 * Initialize WordPress globals by defining all `@wordpress` modules on the
 * window.wp namespace. This allows plugin scripts loaded from the editor
 * assets endpoint to access these modules.
 *
 * @return {void}
 */
export async function initializeWordPressGlobals() {
	window.jQuery = jquery; // Expose jQuery for plugins

	// Initialize the wp namespace if it doesn't exist
	window.wp = window.wp || {};

	// Define all WordPress modules on window.wp, shaped as core builds them:
	// packages core flags `wpScriptDefaultExport` expose their default export.
	window.wp.a11y = toCommonJS( a11y );
	window.wp.apiFetch = apiFetch.default || apiFetch;
	window.wp.autop = toCommonJS( autop );
	window.wp.blob = toCommonJS( blob );
	window.wp.blockEditor = toCommonJS( blockEditor );
	window.wp.blockLibrary = toCommonJS( blockLibrary );
	window.wp.blockSerializationDefaultParser = toCommonJS(
		blockSerializationDefaultParser
	);
	window.wp.blocks = toCommonJS( blocks );
	window.wp.commands = toCommonJS( commands );
	window.wp.components = toCommonJS( components );
	window.wp.compose = toCommonJS( compose );
	window.wp.coreData = toCommonJS( coreData );
	window.wp.data = toCommonJS( data );
	window.wp.dataControls = toCommonJS( dataControls );
	window.wp.date = toCommonJS( date );
	window.wp.deprecated = deprecated.default || deprecated;
	window.wp.dom = toCommonJS( dom );
	window.wp.domReady = domReady.default || domReady;
	window.wp.editPost = toCommonJS( editPost );
	window.wp.editor = toCommonJS( editor );
	window.wp.element = toCommonJS( element );
	window.wp.escapeHtml = toCommonJS( escapeHtml );
	window.wp.formatLibrary = toCommonJS( formatLibrary );
	window.wp.globalStylesEngine = toCommonJS( globalStylesEngine );
	// hooks and i18n are initialized via wordpress-i18n.js
	// Ensure they exist (they should, but handle case where wordpress-i18n.js hasn't loaded)
	if ( ! window.wp.hooks ) {
		throw new Error(
			'wordpress-i18n.js must be loaded before wordpress-globals.js'
		);
	}
	window.wp.htmlEntities = toCommonJS( htmlEntities );
	window.wp.icons = toCommonJS( icons );
	window.wp.isShallowEqual = isShallowEqual.default || isShallowEqual;
	window.wp.keycodes = toCommonJS( keycodes );
	window.wp.keyboardShortcuts = toCommonJS( keyboardShortcuts );
	window.wp.mediaUtils = toCommonJS( mediaUtils );
	window.wp.notices = toCommonJS( notices );
	window.wp.patterns = toCommonJS( patterns );
	window.wp.plugins = toCommonJS( plugins );
	window.wp.preferences = toCommonJS( preferences );
	window.wp.preferencesPersistence = toCommonJS( preferencesPersistence );
	window.wp.primitives = toCommonJS( primitives );
	window.wp.privateApis = toCommonJS( privateApis );
	window.wp.priorityQueue = toCommonJS( priorityQueue );
	window.wp.reduxRoutine = reduxRoutine.default || reduxRoutine;
	window.wp.richText = toCommonJS( richText );
	window.wp.router = toCommonJS( router );
	window.wp.serverSideRender = toCommonJS( serverSideRender );
	window.wp.shortcode = toCommonJS( shortcode );
	window.wp.styleEngine = toCommonJS( styleEngine );
	window.wp.sync = toCommonJS( sync );
	window.wp.theme = toCommonJS( theme );
	window.wp.tokenList = tokenList.default || tokenList;
	window.wp.uploadMedia = toCommonJS( uploadMedia );
	window.wp.url = toCommonJS( url );
	window.wp.viewport = toCommonJS( viewport );
	window.wp.warning = warning.default || warning;
	window.wp.widgets = toCommonJS( widgets );
	window.wp.wordcount = toCommonJS( wordcount );

	// Define external dependencies that plugins expect
	window.React = React;
	window.ReactDOM = ReactDOM;
	window.moment = moment;
	window._ = lodash; // Lodash is commonly expected as underscore
	window.lodash = lodash;

	// React JSX runtime for plugin compatibility
	window.ReactJSXRuntime = ReactJSXRuntime;

	// Load wp-util after jQuery and lodash are on window
	await import( '../../vendor/wp-util.js' );
}
