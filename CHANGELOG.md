# GutenbergKit CHANGELOG

---

## Trunk

### Breaking Changes

_None_

### New Features

_None_

### Bug Fixes

_None_

### Internal Changes

_None_

## 0.15.0

### Breaking Changes

-   Move editor loading into the library — callers no longer manage the editor load lifecycle. [#326]
-   AJAX requests now use token authentication instead of cookie-based auth. [#181]

### New Features

-   Add cross-platform HTTP/1.1 parser and local proxy server for iOS and Android. [#367]

### Bug Fixes

-   Filter cross-origin "Script error." from Sentry reports. [#389]
-   Improve iOS bridge stability. [#410]
-   Normalize namespace trailing slash in RESTAPIRepository. [#421]
-   Coerce post ID 0 to nil on both platforms and JS bridge. [#420]

## 0.14.0

### New Features

-   Add local WordPress environment powered by wp-env. [#328]
-   Improve iOS offline editor experience. [#366]
-   Support editing posts of custom post types. [#299]

### Bug Fixes

-   Address Swift compiler warnings. [#306]
-   Open external URLs in system browser on iOS. [#308]
-   Exclude WordPress globals files from externals plugin. [#325]
-   Upgrade @wordpress/format-library and fix PlainText CJS interop. [#323]
-   Resolve Cover block inner UI inaccessible. [#332]
-   Resolve iOS retain cycle in EditorViewController async flow. [#333]
-   Resolve failures from @wordpress/edit-post bump. [#351]
-   Skip editor settings fetch when theme styles are disabled. [#353]
-   Add default typography settings for sites without editor settings. [#355]
-   Include block library editor styles for correct placeholder UI. [#363]
-   Gracefully handle missing translation files. [#364]
-   Improve offline indicator accuracy with HTTP probe. [#387]
-   Replace deprecated EditorSnackbars with SnackbarNotices. [#386]

### Internal Changes

-   Resolve patch-package version mismatch for @wordpress/format-library. [#356]
-   Resolve iOS E2E test failures in block inserter. [#338]
-   Mock oEmbed proxy in embed E2E test to prevent CI flakes. [#354]

## 0.13.2

### Bug Fixes

-   Register MediaFileSchemeHandler for native iOS media insertion. [#309]

## 0.13.1

### Bug Fixes

-   Skip post preloading for non-positive post IDs. [#293]
-   Editor preloading survives blocked asset downloads. [#305]
-   Ensure EditorAssetBundleProvider always replies to JavaScript. [#294]
-   Fetch uncached assets from remote server. [#301]

### Internal Changes

-   Reinstate resolved demo app Swift packages. [#300]
-   Fix test failures and reduce noise. [#303]
-   Add PR guidelines to CLAUDE.md. [#304]

## 0.13.0

### New Features

-   Recover content on WebView refresh via pull model. [#283]
-   Add Android preload list. [#260]

### Internal Changes

-   Mock @wordpress modules throwing import errors. [#290]

## 0.12.1

### New Features

-   Add custom user agent to GutenbergKit WebViews. [#255]

### Bug Fixes

-   Improve preloading robustness. [#288]

### Internal Changes

-   Make targets reuse JavaScript builds. [#265]

## 0.12.0

### Breaking Changes

-   Update to Swift 6 — requires Swift 6 compiler toolchain. [#252]
-   Disable cookies in EditorService. [#246]
-   Remove unused `setup` method from public API. [#244]

### New Features

-   Add support for Editor Settings. [#232]
-   Faster and more robust editor asset management. [#233]
-   Add `editorSettingsEndpoint` to EditorConfiguration. [#245]
-   Add iOS preload list. [#250]
-   Add iOS preload tests. [#253]

### Bug Fixes

-   Fix compilation on macOS. [#248]
-   Android demo app fills viewport. [#275]
-   Toggle the code editor in the iOS demo app. [#274]

### Internal Changes

-   Upgrade dependencies. [#247]
-   Log plugin load and editor initialization failures. [#249]
-   Enable Dependabot for npm dependencies. [#251]
-   Add Claude code review. [#254]
-   Don't send cookies with requests. [#261]
-   Expand and organize documentation. [#273]

## 0.11.1

### Bug Fixes

-   Await configuration before initializing network logging. [#243]

## 0.11.0

### New Features

-   Add native navigation bar overlay so modals better fit in. [#228]
-   Expand error reporting. [#234]
-   Log network activity. [#238]

### Bug Fixes

-   Incorrect media attachment position. [#227]
-   Inline inserter opens native inserter. [#230]

### Internal Changes

-   Improve demo app consistency. [#226]
-   Integrate the React Developer Tools. [#231]
-   Update project configuration, scripts, and documentation. [#229]
-   Improve Makefile. [#237]
-   Improve code quality. [#239]
-   Capture bridge message decoding failure details. [#240]
-   Organize editor setup. [#242]

## 0.10.2

### New Features

-   Discover Android demo app configuration. [#225]

### Bug Fixes

-   Mitigate Android `ERR_UPLOAD_FILE_CHANGE` errors. [#224]

### Internal Changes

-   Remove remote editor variant. [#210]

## 0.10.1

### Bug Fixes

-   Prevent crash from duplicate category pattern keys. [#223]

## 0.10.0

### Breaking Changes

-   Increase deployment target to iOS 17. [#189]
-   Remove unused `EditorNetworking`. [#208]

### New Features

-   Add EditorViewModel. [#192]
-   Auto-focus when creating a new post. [#191]
-   Add block inserter flag and initial infrastructure. [#193]
-   Add basic block inserter features: grid, search, icons, ordering. [#196]
-   Native inserter: implement block insertion. [#199]
-   Add infrastructure for injecting media pickers. [#201]
-   Native inserter: add initial Photos integration. [#203]
-   Native inserter: add inline compact PhotosPicker. [#212]
-   Native inserter: show as popover on iPad. [#215]
-   Native inserter: patterns. [#207]
-   Native inserter: apply theme styles for pattern previews. [#218]
-   Native inserter: private pattern categories and localizable titles. [#219]
-   Native inserter: poor man internationalization. [#220]
-   Native inserter: add support for inserting existing site media. [#221]
-   Enable image resizing on mobile devices. [#213]
-   Block toolbar indicates scrollable area. [#214]
-   Bundled editor supports plugins. [#209]
-   Improve editor load resiliency. [#222]
-   Demo app navigates history state. [#187]
-   Demo editor toggles code editor mode. [#188]
-   Modernize Android demo app. [#194]
-   iOS demo app discovers remote editors. [#197]

### Bug Fixes

-   Defer remote editor references to @wordpress modules. [#198]
-   Native inserter: fix SVG rendering. [#205]
-   Display drag-and-drop indicator. [#217]

### Internal Changes

-   Remove unused code. [#190]
-   Remove unused AnyDecodable. [#200]
-   Refactor Sample App and Logging. [#202]
-   Improve local development server support. [#195]
-   Prevent log noise in test results. [#211]

## 0.9.0

### New Features

-   Theme styles supersede default styles. [#183]
-   Update iOS demo app navigation. [#184]
-   Update Android demo app navigation. [#185]
-   Send modal dialog state to host app. [#186]

## 0.8.1

### Bug Fixes

-   Prevent multiple Android WebView starts. [#175]
-   Block customization without editor settings. [#180]
-   Force visual editor mode to ensure consistency with native host UI. [#182]

### Internal Changes

-   Move remote assets code into individual files. [#176]
-   Add Configuration Builder and tests. [#146]
-   Simplify iOS Settings. [#179]

## 0.8.0

### Breaking Changes

-   Remove unnecessary WebView global configuration. [#172]

### New Features

-   Expose autocomplete triggers and text insertion utility. [#165]
-   Forward original failed HTTP response to web view. [#167]

### Bug Fixes

-   API requests utilize single auth mechanism. [#166]
-   Configure fetch requests occurring during editor initialization. [#168]

### Internal Changes

-   Improve release script. [#163]
-   Improve debugging. [#164]

## 0.7.0

### New Features

-   Bridge AJAX requests to the REST API. [#161]

### Bug Fixes

-   Prevent iOS crash in WebView navigations. [#159]

### Internal Changes

-   Add Claude instructions. [#160]

## 0.6.0

### Breaking Changes

-   Remove iOS cookie configuration. [#157]

### Bug Fixes

-   Remove redundant trailing slash from API namespace configuration. [#158]

## 0.5.0

### New Features

-   Add cookie support. [#144]
-   Add multi-site support to Android demo app. [#155]
-   Android asset caching implementation. [#153]

### Bug Fixes

-   Prevent reused Android WebView crash. [#152]
-   Fix WebView memory leak in GutenbergView. [#156]

### Internal Changes

-   Change editor assets to the cache directory. [#154]

## 0.4.1

_Patch release — no user-facing changes._

## 0.4.0

### New Features

-   Support caching remote assets. [#148]

### Internal Changes

-   Add instructions for remote editor. [#149]
-   Release process script and documentation. [#151]

## 0.3.0

### New Features

-   Internationalization. [#120]
-   Mark content outside of popovers inert. [#145]
-   Sync featured images to host app. [#147]
-   Enable image resizing on mobile devices. [#213]

### Bug Fixes

-   Prevent block inserter horizontal overflow. [#127]
-   Android presents file picker for File block upload. [#128]
-   Mitigate Android text composition oddities. [#134]
-   Scrolling along edges breaks text editing. [#135]
-   Audio block iOS file picker compatibility. [#137]
-   Embed renders. [#140]
-   Prevent inline image crash. [#142]

### Internal Changes

-   Avoid unnecessary editor assets requests. [#126]
-   Set up Vitest. [#131]
-   Update @wordpress/block-editor patch. [#132]
-   Assert useMediaUpload hook. [#141]
-   Revert to AGP 8.7.3. [#143]

[#120]: https://github.com/wordpress-mobile/GutenbergKit/pull/120
[#126]: https://github.com/wordpress-mobile/GutenbergKit/pull/126
[#127]: https://github.com/wordpress-mobile/GutenbergKit/pull/127
[#128]: https://github.com/wordpress-mobile/GutenbergKit/pull/128
[#131]: https://github.com/wordpress-mobile/GutenbergKit/pull/131
[#132]: https://github.com/wordpress-mobile/GutenbergKit/pull/132
[#134]: https://github.com/wordpress-mobile/GutenbergKit/pull/134
[#135]: https://github.com/wordpress-mobile/GutenbergKit/pull/135
[#136]: https://github.com/wordpress-mobile/GutenbergKit/pull/136
[#137]: https://github.com/wordpress-mobile/GutenbergKit/pull/137
[#140]: https://github.com/wordpress-mobile/GutenbergKit/pull/140
[#141]: https://github.com/wordpress-mobile/GutenbergKit/pull/141
[#142]: https://github.com/wordpress-mobile/GutenbergKit/pull/142
[#143]: https://github.com/wordpress-mobile/GutenbergKit/pull/143
[#144]: https://github.com/wordpress-mobile/GutenbergKit/pull/144
[#145]: https://github.com/wordpress-mobile/GutenbergKit/pull/145
[#146]: https://github.com/wordpress-mobile/GutenbergKit/pull/146
[#147]: https://github.com/wordpress-mobile/GutenbergKit/pull/147
[#148]: https://github.com/wordpress-mobile/GutenbergKit/pull/148
[#149]: https://github.com/wordpress-mobile/GutenbergKit/pull/149
[#151]: https://github.com/wordpress-mobile/GutenbergKit/pull/151
[#152]: https://github.com/wordpress-mobile/GutenbergKit/pull/152
[#153]: https://github.com/wordpress-mobile/GutenbergKit/pull/153
[#154]: https://github.com/wordpress-mobile/GutenbergKit/pull/154
[#155]: https://github.com/wordpress-mobile/GutenbergKit/pull/155
[#156]: https://github.com/wordpress-mobile/GutenbergKit/pull/156
[#157]: https://github.com/wordpress-mobile/GutenbergKit/pull/157
[#158]: https://github.com/wordpress-mobile/GutenbergKit/pull/158
[#159]: https://github.com/wordpress-mobile/GutenbergKit/pull/159
[#160]: https://github.com/wordpress-mobile/GutenbergKit/pull/160
[#161]: https://github.com/wordpress-mobile/GutenbergKit/pull/161
[#163]: https://github.com/wordpress-mobile/GutenbergKit/pull/163
[#164]: https://github.com/wordpress-mobile/GutenbergKit/pull/164
[#165]: https://github.com/wordpress-mobile/GutenbergKit/pull/165
[#166]: https://github.com/wordpress-mobile/GutenbergKit/pull/166
[#167]: https://github.com/wordpress-mobile/GutenbergKit/pull/167
[#168]: https://github.com/wordpress-mobile/GutenbergKit/pull/168
[#172]: https://github.com/wordpress-mobile/GutenbergKit/pull/172
[#175]: https://github.com/wordpress-mobile/GutenbergKit/pull/175
[#176]: https://github.com/wordpress-mobile/GutenbergKit/pull/176
[#179]: https://github.com/wordpress-mobile/GutenbergKit/pull/179
[#180]: https://github.com/wordpress-mobile/GutenbergKit/pull/180
[#181]: https://github.com/wordpress-mobile/GutenbergKit/pull/181
[#182]: https://github.com/wordpress-mobile/GutenbergKit/pull/182
[#183]: https://github.com/wordpress-mobile/GutenbergKit/pull/183
[#184]: https://github.com/wordpress-mobile/GutenbergKit/pull/184
[#185]: https://github.com/wordpress-mobile/GutenbergKit/pull/185
[#186]: https://github.com/wordpress-mobile/GutenbergKit/pull/186
[#187]: https://github.com/wordpress-mobile/GutenbergKit/pull/187
[#188]: https://github.com/wordpress-mobile/GutenbergKit/pull/188
[#189]: https://github.com/wordpress-mobile/GutenbergKit/pull/189
[#190]: https://github.com/wordpress-mobile/GutenbergKit/pull/190
[#191]: https://github.com/wordpress-mobile/GutenbergKit/pull/191
[#192]: https://github.com/wordpress-mobile/GutenbergKit/pull/192
[#193]: https://github.com/wordpress-mobile/GutenbergKit/pull/193
[#194]: https://github.com/wordpress-mobile/GutenbergKit/pull/194
[#195]: https://github.com/wordpress-mobile/GutenbergKit/pull/195
[#196]: https://github.com/wordpress-mobile/GutenbergKit/pull/196
[#197]: https://github.com/wordpress-mobile/GutenbergKit/pull/197
[#198]: https://github.com/wordpress-mobile/GutenbergKit/pull/198
[#199]: https://github.com/wordpress-mobile/GutenbergKit/pull/199
[#200]: https://github.com/wordpress-mobile/GutenbergKit/pull/200
[#201]: https://github.com/wordpress-mobile/GutenbergKit/pull/201
[#202]: https://github.com/wordpress-mobile/GutenbergKit/pull/202
[#203]: https://github.com/wordpress-mobile/GutenbergKit/pull/203
[#205]: https://github.com/wordpress-mobile/GutenbergKit/pull/205
[#207]: https://github.com/wordpress-mobile/GutenbergKit/pull/207
[#208]: https://github.com/wordpress-mobile/GutenbergKit/pull/208
[#209]: https://github.com/wordpress-mobile/GutenbergKit/pull/209
[#210]: https://github.com/wordpress-mobile/GutenbergKit/pull/210
[#211]: https://github.com/wordpress-mobile/GutenbergKit/pull/211
[#212]: https://github.com/wordpress-mobile/GutenbergKit/pull/212
[#213]: https://github.com/wordpress-mobile/GutenbergKit/pull/213
[#214]: https://github.com/wordpress-mobile/GutenbergKit/pull/214
[#215]: https://github.com/wordpress-mobile/GutenbergKit/pull/215
[#217]: https://github.com/wordpress-mobile/GutenbergKit/pull/217
[#218]: https://github.com/wordpress-mobile/GutenbergKit/pull/218
[#219]: https://github.com/wordpress-mobile/GutenbergKit/pull/219
[#220]: https://github.com/wordpress-mobile/GutenbergKit/pull/220
[#221]: https://github.com/wordpress-mobile/GutenbergKit/pull/221
[#222]: https://github.com/wordpress-mobile/GutenbergKit/pull/222
[#223]: https://github.com/wordpress-mobile/GutenbergKit/pull/223
[#224]: https://github.com/wordpress-mobile/GutenbergKit/pull/224
[#225]: https://github.com/wordpress-mobile/GutenbergKit/pull/225
[#226]: https://github.com/wordpress-mobile/GutenbergKit/pull/226
[#227]: https://github.com/wordpress-mobile/GutenbergKit/pull/227
[#228]: https://github.com/wordpress-mobile/GutenbergKit/pull/228
[#229]: https://github.com/wordpress-mobile/GutenbergKit/pull/229
[#230]: https://github.com/wordpress-mobile/GutenbergKit/pull/230
[#231]: https://github.com/wordpress-mobile/GutenbergKit/pull/231
[#232]: https://github.com/wordpress-mobile/GutenbergKit/pull/232
[#233]: https://github.com/wordpress-mobile/GutenbergKit/pull/233
[#234]: https://github.com/wordpress-mobile/GutenbergKit/pull/234
[#237]: https://github.com/wordpress-mobile/GutenbergKit/pull/237
[#238]: https://github.com/wordpress-mobile/GutenbergKit/pull/238
[#239]: https://github.com/wordpress-mobile/GutenbergKit/pull/239
[#240]: https://github.com/wordpress-mobile/GutenbergKit/pull/240
[#242]: https://github.com/wordpress-mobile/GutenbergKit/pull/242
[#243]: https://github.com/wordpress-mobile/GutenbergKit/pull/243
[#244]: https://github.com/wordpress-mobile/GutenbergKit/pull/244
[#245]: https://github.com/wordpress-mobile/GutenbergKit/pull/245
[#246]: https://github.com/wordpress-mobile/GutenbergKit/pull/246
[#247]: https://github.com/wordpress-mobile/GutenbergKit/pull/247
[#248]: https://github.com/wordpress-mobile/GutenbergKit/pull/248
[#249]: https://github.com/wordpress-mobile/GutenbergKit/pull/249
[#250]: https://github.com/wordpress-mobile/GutenbergKit/pull/250
[#251]: https://github.com/wordpress-mobile/GutenbergKit/pull/251
[#252]: https://github.com/wordpress-mobile/GutenbergKit/pull/252
[#253]: https://github.com/wordpress-mobile/GutenbergKit/pull/253
[#254]: https://github.com/wordpress-mobile/GutenbergKit/pull/254
[#255]: https://github.com/wordpress-mobile/GutenbergKit/pull/255
[#260]: https://github.com/wordpress-mobile/GutenbergKit/pull/260
[#261]: https://github.com/wordpress-mobile/GutenbergKit/pull/261
[#265]: https://github.com/wordpress-mobile/GutenbergKit/pull/265
[#273]: https://github.com/wordpress-mobile/GutenbergKit/pull/273
[#274]: https://github.com/wordpress-mobile/GutenbergKit/pull/274
[#275]: https://github.com/wordpress-mobile/GutenbergKit/pull/275
[#276]: https://github.com/wordpress-mobile/GutenbergKit/pull/276
[#283]: https://github.com/wordpress-mobile/GutenbergKit/pull/283
[#288]: https://github.com/wordpress-mobile/GutenbergKit/pull/288
[#290]: https://github.com/wordpress-mobile/GutenbergKit/pull/290
[#293]: https://github.com/wordpress-mobile/GutenbergKit/pull/293
[#294]: https://github.com/wordpress-mobile/GutenbergKit/pull/294
[#299]: https://github.com/wordpress-mobile/GutenbergKit/pull/299
[#300]: https://github.com/wordpress-mobile/GutenbergKit/pull/300
[#301]: https://github.com/wordpress-mobile/GutenbergKit/pull/301
[#303]: https://github.com/wordpress-mobile/GutenbergKit/pull/303
[#304]: https://github.com/wordpress-mobile/GutenbergKit/pull/304
[#305]: https://github.com/wordpress-mobile/GutenbergKit/pull/305
[#306]: https://github.com/wordpress-mobile/GutenbergKit/pull/306
[#308]: https://github.com/wordpress-mobile/GutenbergKit/pull/308
[#309]: https://github.com/wordpress-mobile/GutenbergKit/pull/309
[#323]: https://github.com/wordpress-mobile/GutenbergKit/pull/323
[#325]: https://github.com/wordpress-mobile/GutenbergKit/pull/325
[#326]: https://github.com/wordpress-mobile/GutenbergKit/pull/326
[#328]: https://github.com/wordpress-mobile/GutenbergKit/pull/328
[#332]: https://github.com/wordpress-mobile/GutenbergKit/pull/332
[#333]: https://github.com/wordpress-mobile/GutenbergKit/pull/333
[#338]: https://github.com/wordpress-mobile/GutenbergKit/pull/338
[#351]: https://github.com/wordpress-mobile/GutenbergKit/pull/351
[#353]: https://github.com/wordpress-mobile/GutenbergKit/pull/353
[#354]: https://github.com/wordpress-mobile/GutenbergKit/pull/354
[#355]: https://github.com/wordpress-mobile/GutenbergKit/pull/355
[#356]: https://github.com/wordpress-mobile/GutenbergKit/pull/356
[#363]: https://github.com/wordpress-mobile/GutenbergKit/pull/363
[#364]: https://github.com/wordpress-mobile/GutenbergKit/pull/364
[#366]: https://github.com/wordpress-mobile/GutenbergKit/pull/366
[#367]: https://github.com/wordpress-mobile/GutenbergKit/pull/367
[#386]: https://github.com/wordpress-mobile/GutenbergKit/pull/386
[#387]: https://github.com/wordpress-mobile/GutenbergKit/pull/387
[#389]: https://github.com/wordpress-mobile/GutenbergKit/pull/389
[#410]: https://github.com/wordpress-mobile/GutenbergKit/pull/410
[#420]: https://github.com/wordpress-mobile/GutenbergKit/pull/420
[#421]: https://github.com/wordpress-mobile/GutenbergKit/pull/421
