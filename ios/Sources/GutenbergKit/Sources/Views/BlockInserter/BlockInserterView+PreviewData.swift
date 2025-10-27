#if DEBUG
import Foundation

extension EditorBlock {
    static let mocks: [EditorBlock] = [
        // Text blocks
        EditorBlock(
            id: "core/paragraph",
            name: "core/paragraph",
            title: "Paragraph",
            description: "Start with the basic building block of all narrative.",
            category: "text",
            keywords: ["text", "paragraph"],
            icon: paragraphSVG
        ),
        EditorBlock(
            id: "core/heading",
            name: "core/heading",
            title: "Heading",
            description: "Introduce new sections and organize content to help visitors find what they need.",
            category: "text",
            keywords: ["title", "heading"],
            icon: headingSVG
        ),
        EditorBlock(
            id: "core/list",
            name: "core/list",
            title: "List",
            description: "Create a bulleted or numbered list.",
            category: "text",
            keywords: ["bullet", "number", "list"],
            icon: listSVG
        ),
        EditorBlock(
            id: "core/quote",
            name: "core/quote",
            title: "Quote",
            description: "Give quoted text visual emphasis.",
            category: "text",
            keywords: ["quote", "citation"],
            icon: quoteSVG
        ),
        EditorBlock(
            id: "core/code",
            name: "core/code",
            title: "Code",
            description: "Display code snippets that respect your spacing and tabs.",
            category: "text",
            keywords: ["code", "programming"],
            icon: codeSVG
        ),
        EditorBlock(
            id: "core/preformatted",
            name: "core/preformatted",
            title: "Preformatted",
            description: "Add text that respects your spacing and tabs, and also allows styling.",
            category: "text",
            keywords: ["preformatted", "monospace"],
            icon: nil
        ),
        EditorBlock(
            id: "core/pullquote",
            name: "core/pullquote",
            title: "Pullquote",
            description: "Give special visual emphasis to a quote from your text.",
            category: "text",
            keywords: ["pullquote", "quote"],
            icon: quoteSVG
        ),
        EditorBlock(
            id: "core/verse",
            name: "core/verse",
            title: "Verse",
            description: "Insert poetry. Use special spacing formats. Or quote song lyrics.",
            category: "text",
            keywords: ["poetry", "verse"],
            icon: nil
        ),
        EditorBlock(
            id: "core/table",
            name: "core/table",
            title: "Table",
            description: "Create structured content in rows and columns to display information.",
            category: "text",
            keywords: ["table", "rows", "columns"],
            icon: nil
        ),

        // Media blocks
        EditorBlock(
            id: "core/image",
            name: "core/image",
            title: "Image",
            description: "Insert an image to make a visual statement.",
            category: "media",
            keywords: ["photo", "picture"],
            icon: imageSVG
        ),
        EditorBlock(
            id: "core/gallery",
            name: "core/gallery",
            title: "Gallery",
            description: "Display multiple images in a rich gallery.",
            category: "media",
            keywords: ["images", "photos"],
            icon: imageSVG
        ),
        EditorBlock(
            id: "core/audio",
            name: "core/audio",
            title: "Audio",
            description: "Embed a simple audio player.",
            category: "media",
            keywords: ["music", "sound", "podcast"],
            icon: nil
        ),
        EditorBlock(
            id: "core/video",
            name: "core/video",
            title: "Video",
            description: "Embed a video from your media library or upload a new one.",
            category: "media",
            keywords: ["movie", "film"],
            icon: videoSVG
        ),
        EditorBlock(
            id: "core/cover",
            name: "core/cover",
            title: "Cover",
            description: "Add an image or video with a text overlay.",
            category: "media",
            keywords: ["banner", "hero", "cover"],
            icon: nil
        ),
        EditorBlock(
            id: "core/file",
            name: "core/file",
            title: "File",
            description: "Add a link to a downloadable file.",
            category: "media",
            keywords: ["download", "pdf", "document"],
            icon: nil
        ),
        EditorBlock(
            id: "core/media-text",
            name: "core/media-text",
            title: "Media & Text",
            description: "Set media and words side-by-side for a richer layout.",
            category: "media",
            keywords: ["image", "video", "layout"],
            icon: nil
        ),

        // Design blocks
        EditorBlock(
            id: "core/columns",
            name: "core/columns",
            title: "Columns",
            description: "Display content in multiple columns.",
            category: "design",
            keywords: ["layout", "columns"],
            icon: nil
        ),
        EditorBlock(
            id: "core/group",
            name: "core/group",
            title: "Group",
            description: "Gather blocks in a container.",
            category: "design",
            keywords: ["container", "wrapper", "group"],
            icon: nil
        ),
        EditorBlock(
            id: "core/separator",
            name: "core/separator",
            title: "Separator",
            description: "Create a break between ideas or sections.",
            category: "design",
            keywords: ["divider", "hr"],
            icon: nil
        ),
        EditorBlock(
            id: "core/spacer",
            name: "core/spacer",
            title: "Spacer",
            description: "Add white space between blocks.",
            category: "design",
            keywords: ["space", "gap"],
            icon: nil
        ),
        EditorBlock(
            id: "core/buttons",
            name: "core/buttons",
            title: "Buttons",
            description: "Prompt visitors to take action with a group of button-style links.",
            category: "design",
            keywords: ["button", "link", "cta"],
            icon: buttonSVG
        ),
        EditorBlock(
            id: "core/more",
            name: "core/more",
            title: "More",
            description: "Content before this block will be shown in the excerpt on your archives page.",
            category: "design",
            keywords: ["read more", "excerpt"],
            icon: nil
        ),

        // Widget blocks
        EditorBlock(
            id: "core/search",
            name: "core/search",
            title: "Search",
            description: "Help visitors find your content.",
            category: "widgets",
            keywords: ["find", "search"]
        ),
        EditorBlock(
            id: "core/archives",
            name: "core/archives",
            title: "Archives",
            description: "Display a date archive of your posts.",
            category: "widgets",
            keywords: ["archive", "history"],
            icon: nil
        ),
        EditorBlock(
            id: "core/categories",
            name: "core/categories",
            title: "Categories",
            description: "Display a list of all categories.",
            category: "widgets",
            keywords: ["category", "taxonomy"],
            icon: nil
        ),

        // Embed blocks
        EditorBlock(
            id: "core-embed/youtube",
            name: "core-embed/youtube",
            title: "YouTube",
            description: "Embed a YouTube video.",
            category: "embed",
            keywords: ["video", "youtube"],
            icon: nil
        ),
        EditorBlock(
            id: "core-embed/twitter",
            name: "core-embed/twitter",
            title: "Twitter",
            description: "Embed a tweet.",
            category: "embed",
            keywords: ["tweet", "twitter"],
            icon: nil
        ),
        EditorBlock(
            id: "core-embed/vimeo",
            name: "core-embed/vimeo",
            title: "Vimeo",
            description: "Embed a Vimeo video.",
            category: "embed",
            keywords: ["video", "vimeo"],
            icon: nil
        ),
        EditorBlock(
            id: "core-embed/instagram",
            name: "core-embed/instagram",
            title: "Instagram",
            description: "Embed an Instagram post.",
            category: "embed",
            keywords: ["instagram", "photo"],
            icon: nil
        ),

        // Additional common blocks
        EditorBlock(
            id: "core/html",
            name: "core/html",
            title: "Custom HTML",
            description: "Add custom HTML code and preview it as you edit.",
            category: "widgets",
            keywords: ["html", "code", "custom"],
            icon: codeSVG
        ),
        EditorBlock(
            id: "core/shortcode",
            name: "core/shortcode",
            title: "Shortcode",
            description: "Insert additional custom elements with WordPress shortcodes.",
            category: "widgets",
            keywords: ["shortcode", "custom"],
            icon: nil
        ),
        EditorBlock(
            id: "core/social-links",
            name: "core/social-links",
            title: "Social Icons",
            description: "Display icons linking to your social media profiles.",
            category: "widgets",
            keywords: ["social", "links", "icons"],
            icon: nil
        )
    ]

    // MARK: - Placeholder SVG Icons

    private static let paragraphSVG = """
     <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" aria-hidden="true"><path d="m9.99609 14v-.2251l.00391.0001v6.225h1.5v-14.5h2.5v14.5h1.5v-14.5h3v-1.5h-8.50391c-2.76142 0-5 2.23858-5 5 0 2.7614 2.23858 5 5 5z"></path></svg>
    """

    private static let headingSVG = """
     <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" aria-hidden="true"><path d="M6 5V18.5911L12 13.8473L18 18.5911V5H6Z"></path></svg>
    """

    private static let listSVG = """
     <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg" aria-hidden="true"><path d="M4 4v1.5h16V4H4zm8 8.5h8V11h-8v1.5zM4 20h16v-1.5H4V20zm4-8c0-1.1-.9-2-2-2s-2 .9-2 2 .9 2 2 2 2-.9 2-2z"></path></svg>
    """

    private static let quoteSVG = """
    <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg" aria-hidden="true"><path d="M13 6v6h5.2v4c0 .8-.2 1.4-.5 1.7-.6.6-1.6.6-2.5.5h-.3v1.5h.5c1 0 2.3-.1 3.3-1 .6-.6 1-1.6 1-2.8V6H13zm-9 6h5.2v4c0 .8-.2 1.4-.5 1.7-.6.6-1.6.6-2.5.5h-.3v1.5h.5c1 0 2.3-.1 3.3-1 .6-.6 1-1.6 1-2.8V6H4v6z"></path></svg>
    """

    private static let imageSVG = """
    <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg" aria-hidden="true"><path d="M19 3H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zM5 4.5h14c.3 0 .5.2.5.5v8.4l-3-2.9c-.3-.3-.8-.3-1 0L11.9 14 9 12c-.3-.2-.6-.2-.8 0l-3.6 2.6V5c-.1-.3.1-.5.4-.5zm14 15H5c-.3 0-.5-.2-.5-.5v-2.4l4.1-3 3 1.9c.3.2.7.2.9-.1L16 12l3.5 3.4V19c0 .3-.2.5-.5.5z"></path></svg>
    """

    private static let videoSVG = """
    <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg" aria-hidden="true"><path d="M18.7 3H5.3C4 3 3 4 3 5.3v13.4C3 20 4 21 5.3 21h13.4c1.3 0 2.3-1 2.3-2.3V5.3C21 4 20 3 18.7 3zm.8 15.7c0 .4-.4.8-.8.8H5.3c-.4 0-.8-.4-.8-.8V5.3c0-.4.4-.8.8-.8h13.4c.4 0 .8.4.8.8v13.4zM10 15l5-3-5-3v6z"></path></svg>
    """

    private static let buttonSVG = """
    <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg" aria-hidden="true"><path d="M8 12.5h8V11H8v1.5Z M19 6.5H5a2 2 0 0 0-2 2V15a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V8.5a2 2 0 0 0-2-2ZM5 8h14a.5.5 0 0 1 .5.5V15a.5.5 0 0 1-.5.5H5a.5.5 0 0 1-.5-.5V8.5A.5.5 0 0 1 5 8Z"></path></svg>
    """

    private static let codeSVG = """
    <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg" aria-hidden="true"><path d="M20.8 10.7l-4.3-4.3-1.1 1.1 4.3 4.3c.1.1.1.3 0 .4l-4.3 4.3 1.1 1.1 4.3-4.3c.7-.8.7-1.9 0-2.6zM4.2 11.8l4.3-4.3-1-1-4.3 4.3c-.7.7-.7 1.8 0 2.5l4.3 4.3 1.1-1.1-4.3-4.3c-.2-.1-.2-.3-.1-.4z"></path></svg>
    """
}
#endif
