/**
 * External dependencies
 */
import React from 'react';
import ReactDOM from 'react-dom';
import moment from 'moment';
import lodash from 'lodash';
import * as ReactJSXRuntime from 'react/jsx-runtime';

/**
 * WordPress dependencies
 */
import * as a11y from '@wordpress/a11y';
import * as apiFetch from '@wordpress/api-fetch';
import * as autop from '@wordpress/autop';
import * as blob from '@wordpress/blob';
import * as blockEditor from '@wordpress/block-editor';
import * as blockLibrary from '@wordpress/block-library';
import * as blocks from '@wordpress/blocks';
import * as commands from '@wordpress/commands';
import * as components from '@wordpress/components';
import * as compose from '@wordpress/compose';
import * as coreCommands from '@wordpress/core-commands';
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
import * as richText from '@wordpress/rich-text';
import * as router from '@wordpress/router';
import * as serverSideRender from '@wordpress/server-side-render';
import * as shortcode from '@wordpress/shortcode';
import * as styleEngine from '@wordpress/style-engine';
import * as tokenList from '@wordpress/token-list';
import * as url from '@wordpress/url';
import * as viewport from '@wordpress/viewport';
import * as warning from '@wordpress/warning';
import * as widgets from '@wordpress/widgets';
import * as wordcount from '@wordpress/wordcount';

/**
 * Initialize WordPress globals by defining all @wordpress modules on the
 * window.wp namespace. This allows plugin scripts loaded from the editor
 * assets endpoint to access these modules.
 *
 * @return {void}
 */
export function initializeWordPressGlobals() {
	// Initialize the wp namespace if it doesn't exist
	window.wp = window.wp || {};

	// Define all WordPress modules on window.wp
	window.wp.a11y = a11y;
	window.wp.apiFetch = apiFetch.default || apiFetch;
	window.wp.autop = autop;
	window.wp.blob = blob;
	window.wp.blockEditor = blockEditor;
	window.wp.blockLibrary = blockLibrary;
	window.wp.blocks = blocks;
	window.wp.commands = commands;
	window.wp.components = components;
	window.wp.compose = compose;
	window.wp.coreCommands = coreCommands;
	window.wp.coreData = coreData;
	window.wp.data = data;
	window.wp.dataControls = dataControls;
	window.wp.date = date;
	window.wp.deprecated = deprecated.default || deprecated;
	window.wp.dom = dom;
	window.wp.domReady = domReady.default || domReady;
	window.wp.editPost = editPost;
	window.wp.editor = editor;
	window.wp.element = element;
	window.wp.escapeHtml = escapeHtml;
	window.wp.formatLibrary = formatLibrary;
	// hooks and i18n are initialized via wordpress-i18n.js
	// Ensure they exist (they should, but handle case where wordpress-i18n.js hasn't loaded)
	if ( ! window.wp.hooks ) {
		throw new Error(
			'wordpress-i18n.js must be loaded before wordpress-globals.js'
		);
	}
	window.wp.htmlEntities = htmlEntities;
	window.wp.icons = icons;
	window.wp.isShallowEqual = isShallowEqual.default || isShallowEqual;
	window.wp.keycodes = keycodes;
	window.wp.keyboardShortcuts = keyboardShortcuts;
	window.wp.mediaUtils = mediaUtils;
	window.wp.notices = notices;
	window.wp.patterns = patterns;
	window.wp.plugins = plugins;
	window.wp.preferences = preferences;
	window.wp.preferencesPersistence = preferencesPersistence;
	window.wp.primitives = primitives;
	window.wp.privateApis = privateApis;
	window.wp.priorityQueue = priorityQueue;
	window.wp.richText = richText;
	window.wp.router = router;
	window.wp.serverSideRender = serverSideRender;
	window.wp.shortcode = shortcode;
	window.wp.styleEngine = styleEngine;
	window.wp.tokenList = tokenList.default || tokenList;
	window.wp.url = url;
	window.wp.viewport = viewport;
	window.wp.warning = warning.default || warning;
	window.wp.widgets = widgets;
	window.wp.wordcount = wordcount;

	// Define external dependencies that plugins expect
	window.React = React;
	window.ReactDOM = ReactDOM;
	window.moment = moment;
	window._ = lodash; // Lodash is commonly expected as underscore
	window.lodash = lodash;

	// React JSX runtime for plugin compatibility
	window.ReactJSXRuntime = ReactJSXRuntime;
}

initializeWordPressGlobals();
