# Mobile Editor Tests

## Smoke Tests

**Purpose:** Verify the editor's core functionality: writing/formatting text, uploading media, saving/publishing, and basic block manipulation.

### S.1. Add a link to a paragraph

-   **Steps:**
    -   Add a Paragraph, List, or Heading block.
    -   Type some text.
    -   Apply a link to the text.
-   **Expected Outcome:** Link is applied to the text as expected.

### S.2. Undo/Redo Actions

-   **Steps:**
    -   Add, remove, and edit blocks and text.
    -   Use Undo and Redo buttons.
-   **Expected Outcome:** Editor correctly undoes and redoes actions, restoring previous states.

### S.3. Upload an image

-   **Steps:**
    -   Add an Image block.
    -   Tap "Choose from device" and select an image.
-   **Expected Outcome:** Image uploads and displays in the block. An activity indicator is shown while the image is uploading.

### S.4. Upload an video

-   **Steps:**
    -   Add a Video block.
    -   Tap "Choose from device" and select a video.
-   **Expected Outcome:** Video uploads and displays in the block. An activity indicator is shown while the video is uploading.

### S.5. Reorder blocks

-   **Steps:**
    -   Add several content blocks to a post.
    -   Select a block.
    -   Use the up/down arrows in the block toolbar to relocate the block.
-   **Expected Outcome:** The block ordering is updated as expected.

### S.6. Save and publish a post

-   **Steps:**
    -   Create a new post with text and media.
    -   Save as draft, then publish.
-   **Expected Outcome:** Post is saved and published successfully; content appears as expected.

## Functionality Tests

**Purpose:** Validate deeper content and formatting features, advanced block settings, and robust editor behaviors.

### F.1. Text alignment options

-   **Steps:**
    -   Add a Paragraph or Verse block.
    -   Type text and use alignment options (left, center, right).
-   **Expected Outcome:** Selected alignment is applied to the block content.

### F.2. Add and preview embedded content

-   **Steps:**
    -   Add a Shortcode or Embed block.
    -   Insert a YouTube or Twitter link.
    -   Preview the post.
-   **Expected Outcome:** Embedded content (e.g., YouTube video) displays correctly in preview.

### F.3. Buttons block: add, remove, and style buttons

-   **Steps:**
    -   Add a Buttons block.
    -   Add multiple buttons, remove one, and verify focus.
    -   Apply alignment, background, and text color changes.
-   **Expected Outcome:** Buttons can be added/removed; styles and alignment update as expected.

### F.4. Color and gradient customization

-   **Steps:**
    -   Add a block supporting color (e.g., Buttons, Cover).
    -   Open color settings, switch between solid and gradient, pick custom colors, and apply.
-   **Expected Outcome:** Selected colors/gradients are applied; UI updates accordingly.

### F.5. Gallery block: image uploads and captions

-   **Steps:**
    -   Add a Gallery block, upload multiple images.
    -   Add captions to gallery and individual images, apply formatting.
-   **Expected Outcome:** An activity indicator is shown while the images are uploading. Captions and formatting display as expected.

### F.6. Pattern insertion

-   **Steps:**
    -   Insert a pattern from the inserter.
-   **Expected Outcome:** Pattern content appears.

### F.7. Upload an audio file

Known issue: [Audio block unable to upload expected file formats](https://github.com/wordpress-mobile/GutenbergKit/issues/123)

-   **Steps:**
    -   Add an Audio block.
    -   Tap "Choose from device" and select an audio file.
-   **Expected Outcome:** Audio uploads and displays in the block. An activity indicator is shown while the audio is uploading.

### F.8. Upload a file

Known issue: [File block unable to upload expected file formats](https://github.com/wordpress-mobile/GutenbergKit/issues/124)

-   **Steps:**
    -   Add a File block.
    -   Tap "Choose from device" and select a file.
-   **Expected Outcome:** File uploads, filename and download button appear when upload completes.
