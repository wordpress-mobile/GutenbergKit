import * as __WEBPACK_EXTERNAL_MODULE__wordpress_interactivity_8e89b257__ from "@wordpress/interactivity";
/******/ var __webpack_modules__ = ({

/***/ 225:
/***/ ((__unused_webpack_module, __webpack_exports__, __webpack_require__) => {

/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   B: () => (/* binding */ updateHead),
/* harmony export */   J: () => (/* binding */ fetchHeadAssets)
/* harmony export */ });
/**
 * Helper to update only the necessary tags in the head.
 *
 * @async
 * @param {Array} newHead The head elements of the new page.
 */
const updateHead = async newHead => {
  // Helper to get the tag id store in the cache.
  const getTagId = tag => tag.id || tag.outerHTML;

  // Map incoming head tags by their content.
  const newHeadMap = new Map();
  for (const child of newHead) {
    newHeadMap.set(getTagId(child), child);
  }
  const toRemove = [];

  // Detect nodes that should be added or removed.
  for (const child of document.head.children) {
    const id = getTagId(child);
    // Always remove styles and links as they might change.
    if (child.nodeName === 'LINK' || child.nodeName === 'STYLE') {
      toRemove.push(child);
    } else if (newHeadMap.has(id)) {
      newHeadMap.delete(id);
    } else if (child.nodeName !== 'SCRIPT' && child.nodeName !== 'META') {
      toRemove.push(child);
    }
  }

  // Prepare new assets.
  const toAppend = [...newHeadMap.values()];

  // Apply the changes.
  toRemove.forEach(n => n.remove());
  document.head.append(...toAppend);
};

/**
 * Fetches and processes head assets (stylesheets and scripts) from a specified document.
 *
 * @async
 * @param {Document} doc          The document from which to fetch head assets. It should support standard DOM querying methods.
 * @param {Map}      headElements A map of head elements to modify tracking the URLs of already processed assets to avoid duplicates.
 *
 * @return {Promise<HTMLElement[]>} Returns an array of HTML elements representing the head assets.
 */
const fetchHeadAssets = async (doc, headElements) => {
  const headTags = [];
  const assets = [{
    tagName: 'style',
    selector: 'link[rel=stylesheet]',
    attribute: 'href'
  }, {
    tagName: 'script',
    selector: 'script[src]',
    attribute: 'src'
  }];
  for (const asset of assets) {
    const {
      tagName,
      selector,
      attribute
    } = asset;
    const tags = doc.querySelectorAll(selector);

    // Use Promise.all to wait for fetch to complete
    await Promise.all(Array.from(tags).map(async tag => {
      const attributeValue = tag.getAttribute(attribute);
      if (!headElements.has(attributeValue)) {
        try {
          const response = await fetch(attributeValue);
          const text = await response.text();
          headElements.set(attributeValue, {
            tag,
            text
          });
        } catch (e) {
          // eslint-disable-next-line no-console
          console.error(e);
        }
      }
      const headElement = headElements.get(attributeValue);
      const element = doc.createElement(tagName);
      element.innerText = headElement.text;
      for (const attr of headElement.tag.attributes) {
        element.setAttribute(attr.name, attr.value);
      }
      headTags.push(element);
    }));
  }
  return [doc.querySelector('title'), ...doc.querySelectorAll('style'), ...headTags];
};

/***/ }),

/***/ 638:
/***/ ((module, __webpack_exports__, __webpack_require__) => {

__webpack_require__.a(module, async (__webpack_handle_async_dependencies__, __webpack_async_result__) => { try {
/* harmony export */ __webpack_require__.d(__webpack_exports__, {
/* harmony export */   N: () => (/* binding */ actions),
/* harmony export */   S: () => (/* binding */ state)
/* harmony export */ });
/* harmony import */ var _wordpress_interactivity__WEBPACK_IMPORTED_MODULE_0__ = __webpack_require__(998);
/* harmony import */ var _head__WEBPACK_IMPORTED_MODULE_1__ = __webpack_require__(225);
var _getConfig$navigation;
/**
 * WordPress dependencies
 */


/**
 * Internal dependencies
 */

const {
  directivePrefix,
  getRegionRootFragment,
  initialVdom,
  toVdom,
  render,
  parseInitialData,
  populateInitialData,
  batch
} = (0,_wordpress_interactivity__WEBPACK_IMPORTED_MODULE_0__.privateApis)('I acknowledge that using private APIs means my theme or plugin will inevitably break in the next version of WordPress.');

// Check if the navigation mode is full page or region based.
const navigationMode = (_getConfig$navigation = (0,_wordpress_interactivity__WEBPACK_IMPORTED_MODULE_0__.getConfig)('core/router').navigationMode) !== null && _getConfig$navigation !== void 0 ? _getConfig$navigation : 'regionBased';

// The cache of visited and prefetched pages, stylesheets and scripts.
const pages = new Map();
const headElements = new Map();

// Helper to remove domain and hash from the URL. We are only interesting in
// caching the path and the query.
const getPagePath = url => {
  const u = new URL(url, window.location);
  return u.pathname + u.search;
};

// Fetch a new page and convert it to a static virtual DOM.
const fetchPage = async (url, {
  html
}) => {
  try {
    if (!html) {
      const res = await window.fetch(url);
      if (res.status !== 200) {
        return false;
      }
      html = await res.text();
    }
    const dom = new window.DOMParser().parseFromString(html, 'text/html');
    return regionsToVdom(dom);
  } catch (e) {
    return false;
  }
};

// Return an object with VDOM trees of those HTML regions marked with a
// `router-region` directive.
const regionsToVdom = async (dom, {
  vdom
} = {}) => {
  const regions = {};
  let head;
  if (true) {
    if (navigationMode === 'fullPage') {
      head = await (0,_head__WEBPACK_IMPORTED_MODULE_1__/* .fetchHeadAssets */ .J)(dom, headElements);
      regions.body = vdom ? vdom.get(document.body) : toVdom(dom.body);
    }
  }
  if (navigationMode === 'regionBased') {
    const attrName = `data-${directivePrefix}-router-region`;
    dom.querySelectorAll(`[${attrName}]`).forEach(region => {
      const id = region.getAttribute(attrName);
      regions[id] = vdom?.has(region) ? vdom.get(region) : toVdom(region);
    });
  }
  const title = dom.querySelector('title')?.innerText;
  const initialData = parseInitialData(dom);
  return {
    regions,
    head,
    title,
    initialData
  };
};

// Render all interactive regions contained in the given page.
const renderRegions = page => {
  batch(() => {
    if (true) {
      if (navigationMode === 'fullPage') {
        // Once this code is tested and more mature, the head should be updated for region based navigation as well.
        (0,_head__WEBPACK_IMPORTED_MODULE_1__/* .updateHead */ .B)(page.head);
        const fragment = getRegionRootFragment(document.body);
        render(page.regions.body, fragment);
      }
    }
    if (navigationMode === 'regionBased') {
      populateInitialData(page.initialData);
      const attrName = `data-${directivePrefix}-router-region`;
      document.querySelectorAll(`[${attrName}]`).forEach(region => {
        const id = region.getAttribute(attrName);
        const fragment = getRegionRootFragment(region);
        render(page.regions[id], fragment);
      });
    }
    if (page.title) {
      document.title = page.title;
    }
  });
};

/**
 * Load the given page forcing a full page reload.
 *
 * The function returns a promise that won't resolve, useful to prevent any
 * potential feedback indicating that the navigation has finished while the new
 * page is being loaded.
 *
 * @param {string} href The page href.
 * @return {Promise} Promise that never resolves.
 */
const forcePageReload = href => {
  window.location.assign(href);
  return new Promise(() => {});
};

// Listen to the back and forward buttons and restore the page if it's in the
// cache.
window.addEventListener('popstate', async () => {
  const pagePath = getPagePath(window.location); // Remove hash.
  const page = pages.has(pagePath) && (await pages.get(pagePath));
  if (page) {
    renderRegions(page);
    // Update the URL in the state.
    state.url = window.location.href;
  } else {
    window.location.reload();
  }
});

// Initialize the router and cache the initial page using the initial vDOM.
// Once this code is tested and more mature, the head should be updated for region based navigation as well.
if (true) {
  if (navigationMode === 'fullPage') {
    // Cache the scripts. Has to be called before fetching the assets.
    [].map.call(document.querySelectorAll('script[src]'), script => {
      headElements.set(script.getAttribute('src'), {
        tag: script,
        text: script.textContent
      });
    });
    await (0,_head__WEBPACK_IMPORTED_MODULE_1__/* .fetchHeadAssets */ .J)(document, headElements);
  }
}
pages.set(getPagePath(window.location), Promise.resolve(regionsToVdom(document, {
  vdom: initialVdom
})));

// Check if the link is valid for client-side navigation.
const isValidLink = ref => ref && ref instanceof window.HTMLAnchorElement && ref.href && (!ref.target || ref.target === '_self') && ref.origin === window.location.origin && !ref.pathname.startsWith('/wp-admin') && !ref.pathname.startsWith('/wp-login.php') && !ref.getAttribute('href').startsWith('#') && !new URL(ref.href).searchParams.has('_wpnonce');

// Check if the event is valid for client-side navigation.
const isValidEvent = event => event && event.button === 0 &&
// Left clicks only.
!event.metaKey &&
// Open in new tab (Mac).
!event.ctrlKey &&
// Open in new tab (Windows).
!event.altKey &&
// Download.
!event.shiftKey && !event.defaultPrevented;

// Variable to store the current navigation.
let navigatingTo = '';
const {
  state,
  actions
} = (0,_wordpress_interactivity__WEBPACK_IMPORTED_MODULE_0__.store)('core/router', {
  state: {
    url: window.location.href,
    navigation: {
      hasStarted: false,
      hasFinished: false,
      texts: {}
    }
  },
  actions: {
    /**
     * Navigates to the specified page.
     *
     * This function normalizes the passed href, fetchs the page HTML if
     * needed, and updates any interactive regions whose contents have
     * changed. It also creates a new entry in the browser session history.
     *
     * @param {string}  href                               The page href.
     * @param {Object}  [options]                          Options object.
     * @param {boolean} [options.force]                    If true, it forces re-fetching the URL.
     * @param {string}  [options.html]                     HTML string to be used instead of fetching the requested URL.
     * @param {boolean} [options.replace]                  If true, it replaces the current entry in the browser session history.
     * @param {number}  [options.timeout]                  Time until the navigation is aborted, in milliseconds. Default is 10000.
     * @param {boolean} [options.loadingAnimation]         Whether an animation should be shown while navigating. Default to `true`.
     * @param {boolean} [options.screenReaderAnnouncement] Whether a message for screen readers should be announced while navigating. Default to `true`.
     *
     * @return {Promise} Promise that resolves once the navigation is completed or aborted.
     */
    *navigate(href, options = {}) {
      const {
        clientNavigationDisabled
      } = (0,_wordpress_interactivity__WEBPACK_IMPORTED_MODULE_0__.getConfig)();
      if (clientNavigationDisabled) {
        yield forcePageReload(href);
      }
      const pagePath = getPagePath(href);
      const {
        navigation
      } = state;
      const {
        loadingAnimation = true,
        screenReaderAnnouncement = true,
        timeout = 10000
      } = options;
      navigatingTo = href;
      actions.prefetch(pagePath, options);

      // Create a promise that resolves when the specified timeout ends.
      // The timeout value is 10 seconds by default.
      const timeoutPromise = new Promise(resolve => setTimeout(resolve, timeout));

      // Don't update the navigation status immediately, wait 400 ms.
      const loadingTimeout = setTimeout(() => {
        if (navigatingTo !== href) {
          return;
        }
        if (loadingAnimation) {
          navigation.hasStarted = true;
          navigation.hasFinished = false;
        }
        if (screenReaderAnnouncement) {
          navigation.message = navigation.texts.loading;
        }
      }, 400);
      const page = yield Promise.race([pages.get(pagePath), timeoutPromise]);

      // Dismiss loading message if it hasn't been added yet.
      clearTimeout(loadingTimeout);

      // Once the page is fetched, the destination URL could have changed
      // (e.g., by clicking another link in the meantime). If so, bail
      // out, and let the newer execution to update the HTML.
      if (navigatingTo !== href) {
        return;
      }
      if (page && !page.initialData?.config?.['core/router']?.clientNavigationDisabled) {
        yield renderRegions(page);
        window.history[options.replace ? 'replaceState' : 'pushState']({}, '', href);

        // Update the URL in the state.
        state.url = href;

        // Update the navigation status once the the new page rendering
        // has been completed.
        if (loadingAnimation) {
          navigation.hasStarted = false;
          navigation.hasFinished = true;
        }
        if (screenReaderAnnouncement) {
          // Announce that the page has been loaded. If the message is the
          // same, we use a no-break space similar to the @wordpress/a11y
          // package: https://github.com/WordPress/gutenberg/blob/c395242b8e6ee20f8b06c199e4fc2920d7018af1/packages/a11y/src/filter-message.js#L20-L26
          navigation.message = navigation.texts.loaded + (navigation.message === navigation.texts.loaded ? '\u00A0' : '');
        }

        // Scroll to the anchor if exits in the link.
        const {
          hash
        } = new URL(href, window.location);
        if (hash) {
          document.querySelector(hash)?.scrollIntoView();
        }
      } else {
        yield forcePageReload(href);
      }
    },
    /**
     * Prefetchs the page with the passed URL.
     *
     * The function normalizes the URL and stores internally the fetch
     * promise, to avoid triggering a second fetch for an ongoing request.
     *
     * @param {string}  url             The page URL.
     * @param {Object}  [options]       Options object.
     * @param {boolean} [options.force] Force fetching the URL again.
     * @param {string}  [options.html]  HTML string to be used instead of fetching the requested URL.
     */
    prefetch(url, options = {}) {
      const {
        clientNavigationDisabled
      } = (0,_wordpress_interactivity__WEBPACK_IMPORTED_MODULE_0__.getConfig)();
      if (clientNavigationDisabled) {
        return;
      }
      const pagePath = getPagePath(url);
      if (options.force || !pages.has(pagePath)) {
        pages.set(pagePath, fetchPage(pagePath, options));
      }
    }
  }
});

// Add click and prefetch to all links.
if (true) {
  if (navigationMode === 'fullPage') {
    // Navigate on click.
    document.addEventListener('click', function (event) {
      const ref = event.target.closest('a');
      if (isValidLink(ref) && isValidEvent(event)) {
        event.preventDefault();
        actions.navigate(ref.href);
      }
    }, true);
    // Prefetch on hover.
    document.addEventListener('mouseenter', function (event) {
      if (event.target?.nodeName === 'A') {
        const ref = event.target.closest('a');
        if (isValidLink(ref) && isValidEvent(event)) {
          actions.prefetch(ref.href);
        }
      }
    }, true);
  }
}
__webpack_async_result__();
} catch(e) { __webpack_async_result__(e); } }, 1);

/***/ }),

/***/ 998:
/***/ ((module, __unused_webpack_exports, __webpack_require__) => {

var x = y => { var x = {}; __webpack_require__.d(x, y); return x; }
var y = x => () => x
module.exports = x({ ["getConfig"]: () => __WEBPACK_EXTERNAL_MODULE__wordpress_interactivity_8e89b257__.getConfig, ["privateApis"]: () => __WEBPACK_EXTERNAL_MODULE__wordpress_interactivity_8e89b257__.privateApis, ["store"]: () => __WEBPACK_EXTERNAL_MODULE__wordpress_interactivity_8e89b257__.store });

/***/ })

/******/ });
/************************************************************************/
/******/ // The module cache
/******/ var __webpack_module_cache__ = {};
/******/ 
/******/ // The require function
/******/ function __webpack_require__(moduleId) {
/******/ 	// Check if module is in cache
/******/ 	var cachedModule = __webpack_module_cache__[moduleId];
/******/ 	if (cachedModule !== undefined) {
/******/ 		return cachedModule.exports;
/******/ 	}
/******/ 	// Create a new module (and put it into the cache)
/******/ 	var module = __webpack_module_cache__[moduleId] = {
/******/ 		// no module.id needed
/******/ 		// no module.loaded needed
/******/ 		exports: {}
/******/ 	};
/******/ 
/******/ 	// Execute the module function
/******/ 	__webpack_modules__[moduleId](module, module.exports, __webpack_require__);
/******/ 
/******/ 	// Return the exports of the module
/******/ 	return module.exports;
/******/ }
/******/ 
/************************************************************************/
/******/ /* webpack/runtime/async module */
/******/ (() => {
/******/ 	var webpackQueues = typeof Symbol === "function" ? Symbol("webpack queues") : "__webpack_queues__";
/******/ 	var webpackExports = typeof Symbol === "function" ? Symbol("webpack exports") : "__webpack_exports__";
/******/ 	var webpackError = typeof Symbol === "function" ? Symbol("webpack error") : "__webpack_error__";
/******/ 	var resolveQueue = (queue) => {
/******/ 		if(queue && queue.d < 1) {
/******/ 			queue.d = 1;
/******/ 			queue.forEach((fn) => (fn.r--));
/******/ 			queue.forEach((fn) => (fn.r-- ? fn.r++ : fn()));
/******/ 		}
/******/ 	}
/******/ 	var wrapDeps = (deps) => (deps.map((dep) => {
/******/ 		if(dep !== null && typeof dep === "object") {
/******/ 			if(dep[webpackQueues]) return dep;
/******/ 			if(dep.then) {
/******/ 				var queue = [];
/******/ 				queue.d = 0;
/******/ 				dep.then((r) => {
/******/ 					obj[webpackExports] = r;
/******/ 					resolveQueue(queue);
/******/ 				}, (e) => {
/******/ 					obj[webpackError] = e;
/******/ 					resolveQueue(queue);
/******/ 				});
/******/ 				var obj = {};
/******/ 				obj[webpackQueues] = (fn) => (fn(queue));
/******/ 				return obj;
/******/ 			}
/******/ 		}
/******/ 		var ret = {};
/******/ 		ret[webpackQueues] = x => {};
/******/ 		ret[webpackExports] = dep;
/******/ 		return ret;
/******/ 	}));
/******/ 	__webpack_require__.a = (module, body, hasAwait) => {
/******/ 		var queue;
/******/ 		hasAwait && ((queue = []).d = -1);
/******/ 		var depQueues = new Set();
/******/ 		var exports = module.exports;
/******/ 		var currentDeps;
/******/ 		var outerResolve;
/******/ 		var reject;
/******/ 		var promise = new Promise((resolve, rej) => {
/******/ 			reject = rej;
/******/ 			outerResolve = resolve;
/******/ 		});
/******/ 		promise[webpackExports] = exports;
/******/ 		promise[webpackQueues] = (fn) => (queue && fn(queue), depQueues.forEach(fn), promise["catch"](x => {}));
/******/ 		module.exports = promise;
/******/ 		body((deps) => {
/******/ 			currentDeps = wrapDeps(deps);
/******/ 			var fn;
/******/ 			var getResult = () => (currentDeps.map((d) => {
/******/ 				if(d[webpackError]) throw d[webpackError];
/******/ 				return d[webpackExports];
/******/ 			}))
/******/ 			var promise = new Promise((resolve) => {
/******/ 				fn = () => (resolve(getResult));
/******/ 				fn.r = 0;
/******/ 				var fnQueue = (q) => (q !== queue && !depQueues.has(q) && (depQueues.add(q), q && !q.d && (fn.r++, q.push(fn))));
/******/ 				currentDeps.map((dep) => (dep[webpackQueues](fnQueue)));
/******/ 			});
/******/ 			return fn.r ? promise : getResult();
/******/ 		}, (err) => ((err ? reject(promise[webpackError] = err) : outerResolve(exports)), resolveQueue(queue)));
/******/ 		queue && queue.d < 0 && (queue.d = 0);
/******/ 	};
/******/ })();
/******/ 
/******/ /* webpack/runtime/define property getters */
/******/ (() => {
/******/ 	// define getter functions for harmony exports
/******/ 	__webpack_require__.d = (exports, definition) => {
/******/ 		for(var key in definition) {
/******/ 			if(__webpack_require__.o(definition, key) && !__webpack_require__.o(exports, key)) {
/******/ 				Object.defineProperty(exports, key, { enumerable: true, get: definition[key] });
/******/ 			}
/******/ 		}
/******/ 	};
/******/ })();
/******/ 
/******/ /* webpack/runtime/hasOwnProperty shorthand */
/******/ (() => {
/******/ 	__webpack_require__.o = (obj, prop) => (Object.prototype.hasOwnProperty.call(obj, prop))
/******/ })();
/******/ 
/************************************************************************/
/******/ 
/******/ // startup
/******/ // Load entry module and return exports
/******/ // This entry module used 'module' so it can't be inlined
/******/ var __webpack_exports__ = __webpack_require__(638);
/******/ __webpack_exports__ = await __webpack_exports__;
/******/ var __webpack_exports__actions = __webpack_exports__.N;
/******/ var __webpack_exports__state = __webpack_exports__.S;
/******/ export { __webpack_exports__actions as actions, __webpack_exports__state as state };
/******/ 
