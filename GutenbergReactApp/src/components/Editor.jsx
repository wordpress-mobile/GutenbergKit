/* React */
import { useEffect, useState } from 'react';

/* WordPress */
import {
	BlockEditorKeyboardShortcuts,
	BlockEditorProvider,
	BlockList,
	BlockTools,
	BlockInspector,
	WritingFlow,
	ObserveTyping,
} from '@wordpress/block-editor';
import { Popover, SlotFillProvider } from '@wordpress/components';
import { ShortcutProvider } from '@wordpress/keyboard-shortcuts';
import { registerCoreBlocks } from '@wordpress/block-library';
import { serialize } from '@wordpress/blocks';

import '@wordpress/components/build-style/style.css';
import '@wordpress/block-editor/build-style/style.css';
import '@wordpress/block-library/build-style/style.css';
import '@wordpress/block-library/build-style/editor.css';
import '@wordpress/block-library/build-style/theme.css';

/* Internal */

import EditorToolbar from './EditorToolbar';
import { instantiateBlocksFromContent, useWindowDimensions } from '../misc/Helpers';

// Current editor (assumes can be only one instance).
let editor = {};

function Editor() {
    const [blocks, updateBlocks] = useState([]);
    const { height, width } = useWindowDimensions();
    const [isBlockInspectorShown, setBlockInspectorShown] = useState(false);

    function onInput(blocks) {
        updateBlocks(blocks);
    };

    function onChange(blocks) {
        updateBlocks(blocks);

        // TODO: this doesn't include everything
        const isEmpty = blocks.length === 0 || (blocks[0].name == "core/paragraph" && blocks[0].attributes.content.trim() === "");
        postMessage({ message: "onBlocksChanged", body: { isEmpty: isEmpty } });
    };

    editor.setContent = (content) => {
        updateBlocks(instantiateBlocksFromContent(content));
    };

    editor.setInitialContent = (content) => {
        const blocks = instantiateBlocksFromContent(content);
        onChange(blocks); // TODO: redesign this
        return serialize(blocks);

        editor.setContent(`
        <!-- wp:heading {"level":1} -->
        <h1 class="wp-block-heading" id="the-case-for-gutenberg">The Case for Gutenberg</h1>
        <!-- /wp:heading -->
        
        <!-- wp:paragraph -->
        <p>This post outlines <em>a</em> vision for the mobile editor.&nbsp;There are a couple of (massive) low-hanging fruit that could help us leapfrog the web and the competition.</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:heading -->
        <h2 class="wp-block-heading" id="gutenberg">Gutenberg</h2>
        <!-- /wp:heading -->
        
        <!-- wp:paragraph -->
        <p>Gutenberg is a large-scale project with at least half a million lines of code, 1K+ contributors, and 400 PRs&nbsp;closed in&nbsp;the past month.&nbsp;It supports hundreds of blocks, patterns,&nbsp;Jetpack AI, full-site editing, and&nbsp;numerous&nbsp;other features, including future ones such as live collaboration in&nbsp;<a href="https://wordpress.org/about/roadmap/" target="_blank" rel="noreferrer noopener">Phase 3</a>. </p>
        <!-- /wp:paragraph -->
        
        <!-- wp:paragraph -->
        <p>Gutenberg&nbsp;is built&nbsp;on&nbsp;top&nbsp;of&nbsp;some&nbsp;of the most successful technologies in the past few decades: Web and React. The posts and pages in Gutenberg&nbsp;are&nbsp;stored&nbsp;as HTML, are displayed&nbsp;using&nbsp;web browsers, and are edited using web technologies.&nbsp;<em>Nothing</em>&nbsp;comes even close to the power and efficiency of a highly optimized C/C++ web engine such as WebKit at rendering web content.</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:paragraph -->
        <p>On the other hand, there is <a href="https://github.com/wordpress-mobile/gutenberg-mobile">Gutenberg Mobile</a> which has&nbsp;<a href="https://sparrowp2.wordpress.com/2024/05/07/sparrows-competing-priorities/#comment-1287" target="_blank" rel="noreferrer noopener">no active contributors</a>&nbsp;at the moment. It supports a fraction of the Gutenberg features, is missing from the comments section and other parts of the app, and is an impediment to providing full theme selection and adding full-site editing. The original ideas about <a href="https://make.wordpress.org/mobile/2018/03/21/gutenberg-on-mobile/#comment-19383">abstracting blocks</a> away from HTML have never materialized: while there is a registry of blocks (<a href="https://developer.wordpress.org/block-editor/getting-started/tutorial/#updating-block-json">block.json</a>), <a href="https://developer.wordpress.org/block-editor/getting-started/tutorial/#updating-edit-js-2">editing and rendering</a> is still powered by ReactJS.</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:paragraph -->
        <p>Gutenberg, React, WebKit, and mobile hardware have all made massive advancements in the past years, and there is no catching up. It's a losing battle, and the gap between the core Gutenberg and its mobile counterpart is growing rapidly. So, how can the app position itself to ensure success in the future?</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:heading -->
        <h2 class="wp-block-heading" id="together-strong">Apps Together Strong</h2>
        <!-- /wp:heading -->
        
        <!-- wp:paragraph -->
        <p>With the odds stacked so high against us, there is really only one choice, which requires playing to the strengths of all the available technologies: Gutenberg and WebKit.</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:heading {"level":3} -->
        <h3 class="wp-block-heading" id="gutenberg-strengths"><strong>Gutenberg Strengths</strong> </h3>
        <!-- /wp:heading -->
        
        <!-- wp:list -->
        <ul><!-- wp:list-item -->
        <li>It supports all of the Gutenberg and Jetpack features, including custom blocks, and more</li>
        <!-- /wp:list-item -->
        
        <!-- wp:list-item -->
        <li>The Gutenberg team has done a fantastic job modularizing the framework and making it possible to create any type of editor for any platform powered by its technologies. They specifically&nbsp;<a href="https://github.com/WordPress/gutenberg/issues/53874" target="_blank" rel="noreferrer noopener">invested resources</a>&nbsp;into making sure Gutenberg could be used as a framework and documenting the&nbsp;<a href="https://developer.wordpress.org/block-editor/how-to-guides/platform/custom-block-editor/" target="_blank" rel="noreferrer noopener">process of creating custom editors.</a></li>
        <!-- /wp:list-item -->
        
        <!-- wp:list-item -->
        <li>It's built using React, making easy to build it (<code>npm run build</code>) and embed it in a native app to make it work offline and ensure it loads nearly instantly</li>
        <!-- /wp:list-item -->
        
        <!-- wp:list-item -->
        <li>The web-based editor is already optimized to work on mobile device</li>
        <!-- /wp:list-item -->
        
        <!-- wp:list-item -->
        <li>The main WebKit's components, such as text input, are indistinguishable from the native ones</li>
        <!-- /wp:list-item -->
        
        <!-- wp:list-item -->
        <li>Designed to be highly <a href="https://make.wordpress.org/accessibility/gutenberg-testing/">accessible</a></li>
        <!-- /wp:list-item --></ul>
        <!-- /wp:list -->
        
        <!-- wp:paragraph -->
        <p>There is no beating Gutenberg in any of these aspects.</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:heading {"level":3} -->
        <h3 class="wp-block-heading" id="mobile-strengths"><strong>Mobile Strengths</strong></h3>
        <!-- /wp:heading -->
        
        <!-- wp:list -->
        <ul><!-- wp:list-item -->
        <li>Native navigation</li>
        <!-- /wp:list-item -->
        
        <!-- wp:list-item -->
        <li>Offline mode and a sync engine for posts</li>
        <!-- /wp:list-item -->
        
        <!-- wp:list-item -->
        <li>Device media integration: pickers, cameras, microphones, etc</li>
        <!-- /wp:list-item -->
        
        <!-- wp:list-item -->
        <li>Media uploads: resumable HTTP uploads, background sessions, auto-reties, uploads from disk (<strong>note</strong>: this is where the app <em>should</em> excel, but it supports none of it)</li>
        <!-- /wp:list-item -->
        
        <!-- wp:list-item -->
        <li>On device frameworks and edge compute: <a href="https://developer.apple.com/documentation/speech/">Speech</a>, CoreML, image recognition, and more</li>
        <!-- /wp:list-item -->
        
        <!-- wp:list-item -->
        <li>Multi-touch</li>
        <!-- /wp:list-item -->
        
        <!-- wp:list-item -->
        <li>Persistence and state restoration</li>
        <!-- /wp:list-item --></ul>
        <!-- /wp:list -->
        
        <!-- wp:paragraph -->
        <p>If we want the app to be competitive, the app has to combine these strengths.</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:heading -->
        <h2 class="wp-block-heading" id="user-experience">Target User Experience</h2>
        <!-- /wp:heading -->
        
        <!-- wp:paragraph -->
        <p>Gutenberg is a complex tool with a lot of features for power users. The strength is&nbsp;in&nbsp;consistency: when using the editor on mobile or a tablet, the users should expect to find the same tools in the same places. Any unwarranted discrepancies are going to be detrimental to the experience.</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:paragraph -->
        <p>The web-based editor defines the following main areas: Block Canvas, Block Inserter, Block Toolbars, Block Settings, Block List and Outline. Let's see how they could be translated to the app.</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:image {"id":25828,"sizeSlug":"large","linkDestination":"none"} -->
        <figure class="wp-block-image size-large"><img src="https://jetpackmobile.files.wordpress.com/2024/05/image-4.png?w=1024" alt="" class="wp-image-25828"/></figure>
        <!-- /wp:image -->
        
        <!-- wp:heading {"level":3} -->
        <h3 class="wp-block-heading" id="block-canvas">Block Canvas</h3>
        <!-- /wp:heading -->
        
        <!-- wp:paragraph -->
        <p>The canvas should be rendered using WebKit and be powered entirely by <code>BlockCanvas</code> from <code>@wordpress/block-editor</code>. WebKit is significantly faster than React Native, so there will be significant performance gains, especially when editing long posts. The new editor canvas will support <em>all</em> blocks without any extra effort.</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:paragraph -->
        <p>The user experience will be virtually indistinguishable from using native controls because the main input types in WebKit are rendered using components that are indistinguishable from the native ones, especially anything related to text input.</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:image {"id":25920,"width":"442px","height":"auto","sizeSlug":"full","linkDestination":"none"} -->
        <figure class="wp-block-image size-full is-resized"><img src="https://jetpackmobile.files.wordpress.com/2024/05/screenshot-2024-05-13-at-7.23.04e280afam.png" alt="" class="wp-image-25920" style="width:442px;height:auto"/></figure>
        <!-- /wp:image -->
        
        <!-- wp:heading {"level":3} -->
        <h3 class="wp-block-heading" id="iphone">Block Inserter</h3>
        <!-- /wp:heading -->
        
        <!-- wp:paragraph -->
        <p>The inserter is&nbsp;probably&nbsp;one of the most commonly used parts of the Gutenberg interface. Fortunately, the registry of blocks is platform-independent and API-driven, and that's where the app could differentiate itself a bit from the web and achieve more of a native feel.</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:paragraph -->
        <p>When the user taps "+", the editor will send a message to the app using <code>webkit.messageHandlers</code> and provide a list of blocks to render. The list will use a platform-dependent group list, making it easier to remember the position of the blocks – it's much easier in a vertical list than in a grid.</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:image {"id":25861,"width":"410px","sizeSlug":"full","linkDestination":"none"} -->
        <figure class="wp-block-image size-full is-resized"><img src="https://jetpackmobile.files.wordpress.com/2024/05/screenshot-2024-05-12-at-1.56.22e280afpm.png" alt="" class="wp-image-25861" style="width:410px"/></figure>
        <!-- /wp:image -->
        
        <!-- wp:paragraph -->
        <p>By adding a "Close" button, we'll make the screen more accessible. The "Blocks" menu on the right will allow switching from "Blocks" to "Patterns". The "Patterns" list will be rendered using WebKit.</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:paragraph -->
        <p>(Optional) long-pressing a block will open a description with a preview (web view).</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:heading {"level":3} -->
        <h3 class="wp-block-heading" id="ipad">Block Toolbars</h3>
        <!-- /wp:heading -->
        
        <!-- wp:paragraph -->
        <p>The mobile toolbar in the editor is designed well and is in the right place, and it should continue offering the same experience. However, I would make the following changes:</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:list -->
        <ul><!-- wp:list-item -->
        <li>Enable the native swipe-to-dismiss gestures</li>
        <!-- /wp:list-item -->
        
        <!-- wp:list-item -->
        <li>Replace the "Hide Keyboard" button with the "More" menu to make sure it's easy to access, and it's always in the same place</li>
        <!-- /wp:list-item -->
        
        <!-- wp:list-item -->
        <li>Tighten the spacing: the recommended button size on iOS is 44px</li>
        <!-- /wp:list-item --></ul>
        <!-- /wp:list -->
        
        <!-- wp:paragraph -->
        <p>There are no advantages of rendering the toolbar using React Native, so it should be part of the web view and should not require any custom code.</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:image {"id":25874,"width":"453px","height":"auto","sizeSlug":"large","linkDestination":"none"} -->
        <figure class="wp-block-image size-large is-resized"><img src="https://jetpackmobile.files.wordpress.com/2024/05/image-6.png?w=1016" alt="" class="wp-image-25874" style="width:453px;height:auto"/></figure>
        <!-- /wp:image -->
        
        <!-- wp:paragraph -->
        <p>The app should not attempt to re-implement all the block-related menus, but they could benefit from some iOS and Android specific CSS to make it fit better with the platform conventions.</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:image {"id":26005,"width":"449px","height":"auto","sizeSlug":"full","linkDestination":"none"} -->
        <figure class="wp-block-image size-full is-resized"><img src="https://jetpackmobile.files.wordpress.com/2024/05/image-2-1.png" alt="" class="wp-image-26005" style="width:449px;height:auto"/></figure>
        <!-- /wp:image -->
        
        <!-- wp:heading {"level":3} -->
        <h3 class="wp-block-heading" id="block-settings">Block Settings</h3>
        <!-- /wp:heading -->
        
        <!-- wp:paragraph -->
        <p>The "Block Settings" screen&nbsp;<em>must</em>&nbsp;be rendered&nbsp;using a web view&nbsp;to support custom blocks.&nbsp;However,&nbsp;by&nbsp;using native navigation, the app will make it&nbsp;feel more at home on the platform and&nbsp;make it&nbsp;easier to dismiss&nbsp;it. Gutenberg could also benefit from some minor JS/CSS adjustments&nbsp;–&nbsp;slap rounded corners on everything and increase font size, and it will look fantastic on mobile.</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:image {"id":25877,"width":"458px","height":"auto","sizeSlug":"full","linkDestination":"none"} -->
        <figure class="wp-block-image size-full is-resized"><img src="https://jetpackmobile.files.wordpress.com/2024/05/screenshot-2024-05-12-at-5.09.33e280afpm.png" alt="" class="wp-image-25877" style="width:458px;height:auto"/></figure>
        <!-- /wp:image -->
        
        <!-- wp:paragraph -->
        <p><strong>Note</strong>: If extracting the settings from the React view tree and&nbsp;<code>BlockEditorProvider</code>&nbsp;is too challenging (they can no longer share state), it's not worth using native modals.</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:paragraph -->
        <p>The current "Block Settings" screens in app do not have a native feel and seem use a design language that is unlike both the Gutenberg and the native iOS.</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:image {"id":25879,"width":"457px","height":"auto","sizeSlug":"large","linkDestination":"none"} -->
        <figure class="wp-block-image size-large is-resized"><img src="https://jetpackmobile.files.wordpress.com/2024/05/screenshot-2024-05-12-at-5.14.33e280afpm.png?w=948" alt="" class="wp-image-25879" style="width:457px;height:auto"/></figure>
        <!-- /wp:image -->
        
        <!-- wp:paragraph -->
        <p>It is crucial to keep the grouping, ordering, and naming of these settings&nbsp;consistent with the desktop.&nbsp;The app is doing users a disservice by providing settings that are similar but not quite the same as the web-based ones. Users should not have to learn an entirely new system by opening an editor on mobile.&nbsp;</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:heading {"level":3} -->
        <h3 class="wp-block-heading" id="block-outline">Block Outline</h3>
        <!-- /wp:heading -->
        
        <!-- wp:paragraph -->
        <p>The outline is not currently available in mobile apps, and it could&nbsp;be implemented&nbsp;using a separate web-based screen invoked from the new native context menu.</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:image {"id":26004,"width":"432px","height":"auto","sizeSlug":"full","linkDestination":"none"} -->
        <figure class="wp-block-image size-full is-resized"><img src="https://jetpackmobile.files.wordpress.com/2024/05/screenshot-2024-05-12-at-9.56.18e280afam.png" alt="" class="wp-image-26004" style="width:432px;height:auto"/></figure>
        <!-- /wp:image -->
        
        <!-- wp:paragraph -->
        <p>(Optional) the app should offer keyboard shortcuts and gestures for opening the inspectors.&nbsp;For example, a swipe from&nbsp;the right&nbsp;could open the "Post Preview," and a swipe from&nbsp;the left&nbsp;could open a "Block Outline."</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:heading {"level":3} -->
        <h3 class="wp-block-heading" id="jetpack-ai">Jetpack AI</h3>
        <!-- /wp:heading -->
        
        <!-- wp:paragraph -->
        <p>There are <a href="https://jetpackp2.wordpress.com/2024/05/11/ai-post-from-audio-mobile-app-design-kickoff/">plans</a> to add some parts of the Jetpack AI to the app, but the assistant should, of course, be integrated on the editor level and operate on blocks. By switching to Gutenberg, the app will get all of the Jetpack AI features for free.</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:paragraph -->
        <p><strong>Note</strong>: there is room for improvement for the Jetpack AI assistant. It should <strong>not</strong> be a block.</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:heading {"level":3} -->
        <h3 class="wp-block-heading" id="ipad-1">iPad</h3>
        <!-- /wp:heading -->
        
        <!-- wp:paragraph -->
        <p>Tablets are one of the areas that the Gutenberg Mobile overlooks as the experience is&nbsp;largely&nbsp;unchanged from phones. The iPads are the type of device often used by creating professionals and creators, and the stats prove <a href="https://mc.a8c.com/tracks/trends/?compareby=prop&amp;eventname=jpios_editor_post_published&amp;interval=day&amp;prop=device_info_os&amp;startdate=20240413&amp;stat=uniques">that ~20% of posts</a> are created and edited on iPads despite them being a fraction of the overall user base on iOS. The underpowered editor is likely one of the major reasons why users chose to use Safari instead of the app. But that's not the only iPad problem, and other areas of the app <a href="https://jetpackmobile.wordpress.com/2023/11/16/hackathon-ipad-redesigned/">could use some improvement</a> as well.</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:paragraph -->
        <p>The web-based Gutenberg editor is already superior to the mobile version, so there&nbsp;isn't much&nbsp;we can contribute other than integrating it with the app's database sync engine and native navigation.</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:image {"id":25884,"sizeSlug":"full","linkDestination":"none"} -->
        <figure class="wp-block-image size-full"><img src="https://jetpackmobile.files.wordpress.com/2024/05/screenshot-2024-05-12-at-10.07.34e280afam.png" alt="" class="wp-image-25884"/></figure>
        <!-- /wp:image -->
        
        <!-- wp:list -->
        <ul><!-- wp:list-item -->
        <li>The toolbar bar should <em>not</em> be positioned at the bottom of the screen, which is the hardest area to reach on the iPad. The web version attaches the toolbars to the views&nbsp;that you&nbsp;interact with, which works and feels great on the device.</li>
        <!-- /wp:list-item -->
        
        <!-- wp:list-item -->
        <li>The iPad screen has enough space for displaying settings in the sidebars, and showing it in small modals again only worsens the experience.</li>
        <!-- /wp:list-item -->
        
        <!-- wp:list-item -->
        <li>Apple is leaning heavily into the toolbars (navigation bar) on iPad. The app should provide more easily accessible options by adding them into the navigation bar.</li>
        <!-- /wp:list-item --></ul>
        <!-- /wp:list -->
        
        <!-- wp:paragraph -->
        <p>There are numerous low-hanging fruit on the iPad as almost no work has&nbsp;been done&nbsp;to improve the editing experience on tablets. By addressing the main issues, the app could see a large growth from the tablet users alone.</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:heading {"level":3} -->
        <h3 class="wp-block-heading" id="full-site-editing">Full-Site Editing</h3>
        <!-- /wp:heading -->
        
        <!-- wp:paragraph -->
        <p>By switching to Gutenberg, the app has a clear path for finally adding full-site editing support&nbsp;to the app&nbsp;to empower users to create and manage their sites entirely from their phones and tablets.</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:heading -->
        <h2 class="wp-block-heading" id="technology">Tech Stack</h2>
        <!-- /wp:heading -->
        
        <!-- wp:paragraph -->
        <p>The new editor uses the following technologies:</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:list -->
        <ul><!-- wp:list-item -->
        <li>ReactJS</li>
        <!-- /wp:list-item -->
        
        <!-- wp:list-item -->
        <li>WebKit/Chromium</li>
        <!-- /wp:list-item -->
        
        <!-- wp:list-item -->
        <li>Swift/Kotlin</li>
        <!-- /wp:list-item --></ul>
        <!-- /wp:list -->
        
        <!-- wp:paragraph -->
        <p>The editor&nbsp;is built&nbsp;as a React app, similar to how Gutenberg recommends you&nbsp;<a href="https://developer.wordpress.org/block-editor/how-to-guides/platform/custom-block-editor/" target="_blank" rel="noreferrer noopener">create standalone&nbsp;editors</a>,&nbsp;and is pre-bundled into the app to ensure it can run offline and launches instantly.</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:paragraph -->
        <p><strong>Note</strong>: pre-bundling a React app is fairly easy. You run <code>npm run build</code>, and it creates a build folder that can be directly added to a mobile app. This part has been validated by a PoC and it's a known technology. The only challenge is usually CORS, but it's not insurmountable.</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:paragraph -->
        <p>The JS&lt;-&gt;Native communication is also trivial to achieve. On iOS, it's done using WebKit APIs.</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:list {"ordered":true} -->
        <ol><!-- wp:list-item -->
        <li>The native app registers a message handler:</li>
        <!-- /wp:list-item --></ol>
        <!-- /wp:list -->
        
        <!-- wp:code -->
        <pre class="wp-block-code"><code>func viewDidLoad() {
        <strong>    </strong>let config = WKWebViewConfiguration()
            config.userContentController.add(self, name: "appMessageHandler")
        }</code></pre>
        <!-- /wp:code -->
        
        <!-- wp:paragraph -->
        <p>2. The React app sends the message:</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:code -->
        <pre class="wp-block-code"><code>function postMessage(message) {
            if (window.webkit) {
                window.webkit.messageHandlers.appMessageHandler.postMessage(message)
            };
        };
        
        function Editor() {
            // ...
        
            function onChange(blocks) {
                updateBlocks(blocks);
                postMessage({
                    "message": "onBlocksChanged",
                    "body": blocks
                });
                console.log(blocks);
            };
        
            return (
                &lt;BlockEditorProvider 
                    value={ blocks }
                    onInput={onInput}
                    onChange={onChange}
                &gt;
                    &lt;BlockCanvas height="500px"/&gt;
                &lt;/BlockEditorProvider&gt;
            );
        }</code></pre>
        <!-- /wp:code -->
        
        <!-- wp:paragraph -->
        <p>3. The native app parses the messages:</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:code -->
        <pre class="wp-block-code"><code>func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            let message = try JSEditorMessage(message: message)
            // ...
        }
        
        struct JSEditorMessage {
            let type: JSEditorMessageType
            let body: Any
        
            init?(message: WKScriptMessage) {
                guard let object = message.body as? &#91;String: Any],
                      let type = (object&#91;"message"] as? String).flatMap(JSEditorMessageType.init),
                      let body = object&#91;"body"] else {
        ...</code></pre>
        <!-- /wp:code -->
        
        <!-- wp:paragraph -->
        <p>The app can then send the messages back to the web view by executing custom JavaScript. It's a proven and known technology, so there are no surprises here.</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:paragraph -->
        <p>The PoC implements a message handler that would send the list of blocks to the app on every update, and I added simple decoding for blocks in Swift. The same technique could be used to parse <code>post.content</code> into blocks using <a href="https://developer.apple.com/documentation/javascriptcore">JavaScriptCore</a> with a headless editor, which is something that's missing from the app, and the app could take advantage of it to provide better support for integration with media uploads (as opposed to the existing solution with Regex).</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:heading -->
        <h2 class="wp-block-heading" id="endgame">Endgame</h2>
        <!-- /wp:heading -->
        
        <!-- wp:paragraph -->
        <p>By leveraging the Web's strengths, the app will gain instant access to all of Gutenberg's features: hundreds of blocks, including custom ones, Jetpack AI, optimizations for large screens, post outlines, <a href="https://make.wordpress.org/accessibility/gutenberg-testing/">Gutenberg accessibility</a>, WebKit's performance, and many more. With the support for all the missing blocks and features, there will be a clear path for adding full-site editing to the apps. When new features, like <a href="https://wordpress.org/about/roadmap/">live collaboration</a>, roll out, the app will have a fast path for adopting them.</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:paragraph -->
        <p>By leveraging the Mobile's strengths, this system will have&nbsp;great&nbsp;native navigation, a sync engine, and&nbsp;integration with on-device media and other system frameworks.&nbsp;By tactically adding native views in a few places where they matter, we'll get the best of both worlds—an experience that is distinct and&nbsp;<em>feel</em>s&nbsp;native but is just as powerful as the web-based version.&nbsp;Nobody will be able to tell or&nbsp;will care that some of the&nbsp;parts&nbsp;are rendered&nbsp;using WebKit.</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:paragraph -->
        <p>This&nbsp;is also a great chance to move the editor to a standalone package and provide a clear and concise API for integrating it into apps.&nbsp;The same package could provide wrappers for some of the crucial Gutenberg APIs, such as a block parser that the app&nbsp;<em>needs</em>&nbsp;for implementing&nbsp;background media uploads. A standalone editor will make it easy to&nbsp;integrate in other parts of the apps, namely, the comments section.</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:paragraph -->
        <p>The size of a Gutenberg production build will be just under 20 MB,&nbsp;which is&nbsp;smaller than the current version of the RN-based editor and could  be reduced&nbsp;even further down to 4 MB by zipping it (unzip on first use). It also loads nearly instantly – faster&nbsp;than&nbsp;&nbsp;the&nbsp;web and the RN-based versions. On top of that, it handles large files&nbsp;easily, thanks to WebKit's performance.</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:paragraph -->
        <p>Our goal should be to provide users with the tools necessary to run their businesses from their phones and tablets. Instead of shipping a watered-down version of WordPress, we should lean into its powerful features while maintaining the visual simplicity users expect from mobile apps. By playing to the strengths of each technology, we'll get a better system in every way and will leapfrog the web-based editor and the competition.</p>
        <!-- /wp:paragraph -->
        
        <!-- wp:heading -->
        <h2 class="wp-block-heading" id="references">References</h2>
        <!-- /wp:heading -->
        
        <!-- wp:list -->
        <ul><!-- wp:list-item -->
        <li><a href="https://developer.wordpress.org/block-editor/">Block Editor Handbook</a></li>
        <!-- /wp:list-item -->
        
        <!-- wp:list-item -->
        <li><a href="https://developer.wordpress.org/block-editor/how-to-guides/platform/custom-block-editor/">Building a Custom Block Editor</a></li>
        <!-- /wp:list-item -->
        
        <!-- wp:list-item -->
        <li><a href="https://github.com/getdave/standalone-block-editor">Standalone Gutenberg Block Editor</a></li>
        <!-- /wp:list-item -->
        
        <!-- wp:list-item -->
        <li><a href="https://github.com/WordPress/gutenberg/issues/53874">Gutenberg as a Framework: Streamline the Exprience</a></li>
        <!-- /wp:list-item -->
        
        <!-- wp:list-item -->
        <li><a href="https://make.wordpress.org/mobile/2018/03/21/gutenberg-on-mobile/">Gutenberg on Mobile</a></li>
        <!-- /wp:list-item -->
        
        <!-- wp:list-item -->
        <li><a href="https://developer.wordpress.org/block-editor/getting-started/tutorial/">Tutorial: Build your first custom block</a></li>
        <!-- /wp:list-item -->
        
        <!-- wp:list-item -->
        <li><a href="https://make.wordpress.org/accessibility/gutenberg-testing/">Make WordPress Accessible</a></li>
        <!-- /wp:list-item --></ul>
        <!-- /wp:list -->
        `);
    }

    editor.getContent = () => serialize(blocks);

    // Warning: `useEffect` and functions captured it in can't read the latest useState values,
    // and hence `useRef`.
    useEffect(() => {
        window.editor = editor;
        registerCoreBlocks();
        postMessage({ message: "onEditorLoaded" });
    }, []);

    // Injects CSS styles in the canvas iframe.
    const style = `
    body { 
        padding: 16px; 
        font-family: -apple-system; 
        line-height: 1.55;
    }
    .rich-text:focus { 
        outline: none; 
    }
    .block-editor-block-list__block {
        overflow: hidden;
    }
    `

    // The problem with the editor canvas is that it gets embedded in an iframe
    // so there is no way to style it directly using CSS included in the project itself.
    const styles = [
        { css: style }
    ];

    const settings = {
        hasFixedToolbar: true
    };

    return (
        <div className="playground">
            <ShortcutProvider>
                <SlotFillProvider>
                    <BlockEditorProvider
                        value={blocks}
                        onInput={onInput}
                        onChange={onChange}
                        settings={settings}
                    >
                        <div className="playground__content">
                            <BlockTools>
                                <div className="editor-styles-wrapper">
                                    <BlockEditorKeyboardShortcuts.Register />
                                    <WritingFlow>
                                        <ObserveTyping>
                                            <BlockList />
                                        </ObserveTyping>
                                    </WritingFlow>
                                </div>
                            </BlockTools>
                        </div>
                        <Popover.Slot />
                    </BlockEditorProvider>
                </SlotFillProvider>
            </ShortcutProvider>
        </div>
    );
}

function postMessage(message) {
    if (window.webkit) {
        window.webkit.messageHandlers.editorDelegate.postMessage(message);
    };
};

export default Editor;