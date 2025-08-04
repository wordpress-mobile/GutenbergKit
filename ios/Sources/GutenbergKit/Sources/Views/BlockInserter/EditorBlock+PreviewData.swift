#if DEBUG
import Foundation

enum PreviewData {
    static let sampleBlockTypes: [EditorBlock] = [
        // Text blocks
        EditorBlock(
            name: "core/paragraph",
            title: "Paragraph",
            description: "Start with the basic building block of all narrative.",
            category: "text",
            keywords: ["text", "paragraph"],
        ),
        EditorBlock(
            name: "core/heading",
            title: "Heading",
            description: "Introduce new sections and organize content to help visitors find what they need.",
            category: "text",
            keywords: ["title", "heading"],
        ),
        EditorBlock(
            name: "core/list",
            title: "List",
            description: "Create a bulleted or numbered list.",
            category: "text",
            keywords: ["bullet", "number", "list"],
        ),
        EditorBlock(
            name: "core/quote",
            title: "Quote",
            description: "Give quoted text visual emphasis.",
            category: "text",
            keywords: ["quote", "citation"],
        ),
        EditorBlock(
            name: "core/code",
            title: "Code",
            description: "Display code snippets that respect your spacing and tabs.",
            category: "text",
            keywords: ["code", "programming"],
        ),
        EditorBlock(
            name: "core/preformatted",
            title: "Preformatted",
            description: "Add text that respects your spacing and tabs, and also allows styling.",
            category: "text",
            keywords: ["preformatted", "monospace"],
        ),
        EditorBlock(
            name: "core/pullquote",
            title: "Pullquote",
            description: "Give special visual emphasis to a quote from your text.",
            category: "text",
            keywords: ["pullquote", "quote"],
        ),
        EditorBlock(
            name: "core/verse",
            title: "Verse",
            description: "Insert poetry. Use special spacing formats. Or quote song lyrics.",
            category: "text",
            keywords: ["poetry", "verse"],
        ),
        EditorBlock(
            name: "core/table",
            title: "Table",
            description: "Create structured content in rows and columns to display information.",
            category: "text",
            keywords: ["table", "rows", "columns"],
        ),
        
        // Media blocks
        EditorBlock(
            name: "core/image",
            title: "Image",
            description: "Insert an image to make a visual statement.",
            category: "media",
            keywords: ["photo", "picture"],
        ),
        EditorBlock(
            name: "core/gallery",
            title: "Gallery",
            description: "Display multiple images in a rich gallery.",
            category: "media",
            keywords: ["images", "photos"],
        ),
        EditorBlock(
            name: "core/audio",
            title: "Audio",
            description: "Embed a simple audio player.",
            category: "media",
            keywords: ["music", "sound", "podcast"],
        ),
        EditorBlock(
            name: "core/video",
            title: "Video",
            description: "Embed a video from your media library or upload a new one.",
            category: "media",
            keywords: ["movie", "film"],
        ),
        EditorBlock(
            name: "core/cover",
            title: "Cover",
            description: "Add an image or video with a text overlay.",
            category: "media",
            keywords: ["banner", "hero", "cover"],
        ),
        EditorBlock(
            name: "core/file",
            title: "File",
            description: "Add a link to a downloadable file.",
            category: "media",
            keywords: ["download", "pdf", "document"],
        ),
        EditorBlock(
            name: "core/media-text",
            title: "Media & Text",
            description: "Set media and words side-by-side for a richer layout.",
            category: "media",
            keywords: ["image", "video", "layout"],
        ),
        
        // Design blocks
        EditorBlock(
            name: "core/columns",
            title: "Columns",
            description: "Display content in multiple columns.",
            category: "design",
            keywords: ["layout", "columns"],
        ),
        EditorBlock(
            name: "core/group",
            title: "Group",
            description: "Gather blocks in a container.",
            category: "design",
            keywords: ["container", "wrapper", "group"],
        ),
        EditorBlock(
            name: "core/separator",
            title: "Separator",
            description: "Create a break between ideas or sections.",
            category: "design",
            keywords: ["divider", "hr"],
        ),
        EditorBlock(
            name: "core/spacer",
            title: "Spacer",
            description: "Add white space between blocks.",
            category: "design",
            keywords: ["space", "gap"],
        ),
        EditorBlock(
            name: "core/buttons",
            title: "Buttons",
            description: "Prompt visitors to take action with a group of button-style links.",
            category: "design",
            keywords: ["button", "link", "cta"],
        ),
        EditorBlock(
            name: "core/more",
            title: "More",
            description: "Content before this block will be shown in the excerpt on your archives page.",
            category: "design",
            keywords: ["read more", "excerpt"],
        ),
        
        // Widget blocks
        EditorBlock(
            name: "core/search",
            title: "Search",
            description: "Help visitors find your content.",
            category: "widgets",
            keywords: ["find", "search"],
        ),
        EditorBlock(
            name: "core/archives",
            title: "Archives",
            description: "Display a date archive of your posts.",
            category: "widgets",
            keywords: ["archive", "history"],
        ),
        EditorBlock(
            name: "core/categories",
            title: "Categories",
            description: "Display a list of all categories.",
            category: "widgets",
            keywords: ["category", "taxonomy"],
        ),
        
        // Theme blocks
        EditorBlock(
            name: "core/site-title",
            title: "Site Title",
            description: "Display your site's title.",
            category: "theme",
            keywords: ["title", "site"],
        ),
        EditorBlock(
            name: "core/site-logo",
            title: "Site Logo",
            description: "Display your site's logo.",
            category: "theme",
            keywords: ["logo", "brand"],
        ),
        
        // Embed blocks
        EditorBlock(
            name: "core-embed/youtube",
            title: "YouTube",
            description: "Embed a YouTube video.",
            category: "embed",
            keywords: ["video", "youtube"],
        ),
        EditorBlock(
            name: "core-embed/twitter",
            title: "Twitter",
            description: "Embed a tweet.",
            category: "embed",
            keywords: ["tweet", "twitter"],
        ),
        EditorBlock(
            name: "core-embed/vimeo",
            title: "Vimeo",
            description: "Embed a Vimeo video.",
            category: "embed",
            keywords: ["video", "vimeo"],
        ),
        EditorBlock(
            name: "core-embed/instagram",
            title: "Instagram",
            description: "Embed an Instagram post.",
            category: "embed",
            keywords: ["instagram", "photo"],
        ),
        
        // Jetpack blocks
        EditorBlock(
            name: "jetpack/ai-assistant",
            title: "AI Assistant",
            description: "Generate text, edit content, and get suggestions using AI.",
            category: "text",
            keywords: ["ai", "artificial intelligence", "generate", "write"],
        ),
        EditorBlock(
            name: "jetpack/contact-form",
            title: "Contact Form",
            description: "Add a customizable contact form.",
            category: "widgets",
            keywords: ["form", "contact", "email"],
        ),
        EditorBlock(
            name: "jetpack/markdown",
            title: "Markdown",
            description: "Write posts or pages in plain-text Markdown syntax.",
            category: "text",
            keywords: ["markdown", "md", "formatting"],
        ),
        EditorBlock(
            name: "jetpack/tiled-gallery",
            title: "Tiled Gallery",
            description: "Display multiple images in an elegantly organized tiled layout.",
            category: "media",
            keywords: ["gallery", "images", "photos", "tiled"],
        ),
        EditorBlock(
            name: "jetpack/slideshow",
            title: "Slideshow",
            description: "Display multiple images in a slideshow.",
            category: "media",
            keywords: ["slideshow", "carousel", "gallery"],
        ),
        EditorBlock(
            name: "jetpack/map",
            title: "Map",
            description: "Add an interactive map showing one or more locations.",
            category: "widgets",
            keywords: ["map", "location", "address"],
        ),
        EditorBlock(
            name: "jetpack/business-hours",
            title: "Business Hours",
            description: "Display your business opening hours.",
            category: "widgets",
            keywords: ["hours", "schedule", "business"],
        ),
        EditorBlock(
            name: "jetpack/subscriptions",
            title: "Subscriptions",
            description: "Let visitors subscribe to your blog posts.",
            category: "widgets",
            keywords: ["subscribe", "email", "newsletter"],
        ),
        EditorBlock(
            name: "jetpack/related-posts",
            title: "Related Posts",
            description: "Display a list of related posts.",
            category: "widgets",
            keywords: ["related", "posts", "similar"],
        ),
        
        // Additional common blocks
        EditorBlock(
            name: "core/html",
            title: "Custom HTML",
            description: "Add custom HTML code and preview it as you edit.",
            category: "widgets",
            keywords: ["html", "code", "custom"],
        ),
        EditorBlock(
            name: "core/shortcode",
            title: "Shortcode",
            description: "Insert additional custom elements with WordPress shortcodes.",
            category: "widgets",
            keywords: ["shortcode", "custom"],
        ),
        EditorBlock(
            name: "core/social-links",
            title: "Social Icons",
            description: "Display icons linking to your social media profiles.",
            category: "widgets",
            keywords: ["social", "links", "icons"],
        )
    ]
}
#endif
