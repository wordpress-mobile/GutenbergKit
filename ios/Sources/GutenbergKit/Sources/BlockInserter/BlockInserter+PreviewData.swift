#if DEBUG
import Foundation

enum PreviewData {
    static let sampleBlockTypes: [EditorBlockType] = [
        // Text blocks
        EditorBlockType(
            name: "core/paragraph",
            title: "Paragraph",
            description: "Start with the basic building block of all narrative.",
            category: "text",
            keywords: ["text", "paragraph"],
        ),
        EditorBlockType(
            name: "core/heading",
            title: "Heading",
            description: "Introduce new sections and organize content to help visitors find what they need.",
            category: "text",
            keywords: ["title", "heading"],
        ),
        EditorBlockType(
            name: "core/list",
            title: "List",
            description: "Create a bulleted or numbered list.",
            category: "text",
            keywords: ["bullet", "number", "list"],
        ),
        EditorBlockType(
            name: "core/quote",
            title: "Quote",
            description: "Give quoted text visual emphasis.",
            category: "text",
            keywords: ["quote", "citation"],
        ),
        EditorBlockType(
            name: "core/code",
            title: "Code",
            description: "Display code snippets that respect your spacing and tabs.",
            category: "text",
            keywords: ["code", "programming"],
        ),
        EditorBlockType(
            name: "core/preformatted",
            title: "Preformatted",
            description: "Add text that respects your spacing and tabs, and also allows styling.",
            category: "text",
            keywords: ["preformatted", "monospace"],
        ),
        EditorBlockType(
            name: "core/pullquote",
            title: "Pullquote",
            description: "Give special visual emphasis to a quote from your text.",
            category: "text",
            keywords: ["pullquote", "quote"],
        ),
        EditorBlockType(
            name: "core/verse",
            title: "Verse",
            description: "Insert poetry. Use special spacing formats. Or quote song lyrics.",
            category: "text",
            keywords: ["poetry", "verse"],
        ),
        EditorBlockType(
            name: "core/table",
            title: "Table",
            description: "Create structured content in rows and columns to display information.",
            category: "text",
            keywords: ["table", "rows", "columns"],
        ),
        
        // Media blocks
        EditorBlockType(
            name: "core/image",
            title: "Image",
            description: "Insert an image to make a visual statement.",
            category: "media",
            keywords: ["photo", "picture"],
        ),
        EditorBlockType(
            name: "core/gallery",
            title: "Gallery",
            description: "Display multiple images in a rich gallery.",
            category: "media",
            keywords: ["images", "photos"],
        ),
        EditorBlockType(
            name: "core/audio",
            title: "Audio",
            description: "Embed a simple audio player.",
            category: "media",
            keywords: ["music", "sound", "podcast"],
        ),
        EditorBlockType(
            name: "core/video",
            title: "Video",
            description: "Embed a video from your media library or upload a new one.",
            category: "media",
            keywords: ["movie", "film"],
        ),
        EditorBlockType(
            name: "core/cover",
            title: "Cover",
            description: "Add an image or video with a text overlay.",
            category: "media",
            keywords: ["banner", "hero", "cover"],
        ),
        EditorBlockType(
            name: "core/file",
            title: "File",
            description: "Add a link to a downloadable file.",
            category: "media",
            keywords: ["download", "pdf", "document"],
        ),
        EditorBlockType(
            name: "core/media-text",
            title: "Media & Text",
            description: "Set media and words side-by-side for a richer layout.",
            category: "media",
            keywords: ["image", "video", "layout"],
        ),
        
        // Design blocks
        EditorBlockType(
            name: "core/columns",
            title: "Columns",
            description: "Display content in multiple columns.",
            category: "design",
            keywords: ["layout", "columns"],
        ),
        EditorBlockType(
            name: "core/group",
            title: "Group",
            description: "Gather blocks in a container.",
            category: "design",
            keywords: ["container", "wrapper", "group"],
        ),
        EditorBlockType(
            name: "core/separator",
            title: "Separator",
            description: "Create a break between ideas or sections.",
            category: "design",
            keywords: ["divider", "hr"],
        ),
        EditorBlockType(
            name: "core/spacer",
            title: "Spacer",
            description: "Add white space between blocks.",
            category: "design",
            keywords: ["space", "gap"],
        ),
        EditorBlockType(
            name: "core/buttons",
            title: "Buttons",
            description: "Prompt visitors to take action with a group of button-style links.",
            category: "design",
            keywords: ["button", "link", "cta"],
        ),
        EditorBlockType(
            name: "core/more",
            title: "More",
            description: "Content before this block will be shown in the excerpt on your archives page.",
            category: "design",
            keywords: ["read more", "excerpt"],
        ),
        
        // Widget blocks
        EditorBlockType(
            name: "core/search",
            title: "Search",
            description: "Help visitors find your content.",
            category: "widgets",
            keywords: ["find", "search"],
        ),
        EditorBlockType(
            name: "core/archives",
            title: "Archives",
            description: "Display a date archive of your posts.",
            category: "widgets",
            keywords: ["archive", "history"],
        ),
        EditorBlockType(
            name: "core/categories",
            title: "Categories",
            description: "Display a list of all categories.",
            category: "widgets",
            keywords: ["category", "taxonomy"],
        ),
        
        // Theme blocks
        EditorBlockType(
            name: "core/site-title",
            title: "Site Title",
            description: "Display your site's title.",
            category: "theme",
            keywords: ["title", "site"],
        ),
        EditorBlockType(
            name: "core/site-logo",
            title: "Site Logo",
            description: "Display your site's logo.",
            category: "theme",
            keywords: ["logo", "brand"],
        ),
        
        // Embed blocks
        EditorBlockType(
            name: "core-embed/youtube",
            title: "YouTube",
            description: "Embed a YouTube video.",
            category: "embed",
            keywords: ["video", "youtube"],
        ),
        EditorBlockType(
            name: "core-embed/twitter",
            title: "Twitter",
            description: "Embed a tweet.",
            category: "embed",
            keywords: ["tweet", "twitter"],
        ),
        EditorBlockType(
            name: "core-embed/vimeo",
            title: "Vimeo",
            description: "Embed a Vimeo video.",
            category: "embed",
            keywords: ["video", "vimeo"],
        ),
        EditorBlockType(
            name: "core-embed/instagram",
            title: "Instagram",
            description: "Embed an Instagram post.",
            category: "embed",
            keywords: ["instagram", "photo"],
        ),
        
        // Jetpack blocks
        EditorBlockType(
            name: "jetpack/ai-assistant",
            title: "AI Assistant",
            description: "Generate text, edit content, and get suggestions using AI.",
            category: "text",
            keywords: ["ai", "artificial intelligence", "generate", "write"],
        ),
        EditorBlockType(
            name: "jetpack/contact-form",
            title: "Contact Form",
            description: "Add a customizable contact form.",
            category: "widgets",
            keywords: ["form", "contact", "email"],
        ),
        EditorBlockType(
            name: "jetpack/markdown",
            title: "Markdown",
            description: "Write posts or pages in plain-text Markdown syntax.",
            category: "text",
            keywords: ["markdown", "md", "formatting"],
        ),
        EditorBlockType(
            name: "jetpack/tiled-gallery",
            title: "Tiled Gallery",
            description: "Display multiple images in an elegantly organized tiled layout.",
            category: "media",
            keywords: ["gallery", "images", "photos", "tiled"],
        ),
        EditorBlockType(
            name: "jetpack/slideshow",
            title: "Slideshow",
            description: "Display multiple images in a slideshow.",
            category: "media",
            keywords: ["slideshow", "carousel", "gallery"],
        ),
        EditorBlockType(
            name: "jetpack/map",
            title: "Map",
            description: "Add an interactive map showing one or more locations.",
            category: "widgets",
            keywords: ["map", "location", "address"],
        ),
        EditorBlockType(
            name: "jetpack/business-hours",
            title: "Business Hours",
            description: "Display your business opening hours.",
            category: "widgets",
            keywords: ["hours", "schedule", "business"],
        ),
        EditorBlockType(
            name: "jetpack/subscriptions",
            title: "Subscriptions",
            description: "Let visitors subscribe to your blog posts.",
            category: "widgets",
            keywords: ["subscribe", "email", "newsletter"],
        ),
        EditorBlockType(
            name: "jetpack/related-posts",
            title: "Related Posts",
            description: "Display a list of related posts.",
            category: "widgets",
            keywords: ["related", "posts", "similar"],
        ),
        
        // Additional common blocks
        EditorBlockType(
            name: "core/html",
            title: "Custom HTML",
            description: "Add custom HTML code and preview it as you edit.",
            category: "widgets",
            keywords: ["html", "code", "custom"],
        ),
        EditorBlockType(
            name: "core/shortcode",
            title: "Shortcode",
            description: "Insert additional custom elements with WordPress shortcodes.",
            category: "widgets",
            keywords: ["shortcode", "custom"],
        ),
        EditorBlockType(
            name: "core/social-links",
            title: "Social Icons",
            description: "Display icons linking to your social media profiles.",
            category: "widgets",
            keywords: ["social", "links", "icons"],
        )
    ]
}
#endif