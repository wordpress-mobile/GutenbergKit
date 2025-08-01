import Foundation

extension EditorBlockType {
    /// Returns the SF Symbol icon name for the block type
    var iconName: String {
        switch name {
        // MARK: - Core Text Blocks
        case "core/paragraph": "paragraphsign"
        case "core/heading": "bookmark.fill"
        case "core/list": "list.bullet"
        case "core/quote": "quote.opening"
        case "core/code": "curlybraces"
        case "core/preformatted": "text.alignleft"
        case "core/pullquote": "quote.bubble"
        case "core/verse": "text.quote"
        case "core/table": "tablecells"
            
        // MARK: - Core Media Blocks
        case "core/image": "photo"
        case "core/gallery": "photo.stack"
        case "core/audio": "speaker.wave.2"
        case "core/cover": "photo.tv"
        case "core/file": "doc.text"
        case "core/media-text": "rectangle.split.2x1"
        case "core/video": "video"
            
        // MARK: - Core Design Blocks
        case "core/buttons": "rectangle.3.group"
        case "core/columns": "rectangle.split.3x1"
        case "core/group": "square.on.square"
        case "core/more": "ellipsis"
        case "core/nextpage": "arrow.right.doc.on.clipboard"
        case "core/separator": "minus"
        case "core/spacer": "arrow.up.and.down"
            
        // MARK: - Core Widget Blocks
        case "core/archives": "archivebox"
        case "core/calendar": "calendar"
        case "core/categories": "folder"
        case "core/html": "chevron.left.forwardslash.chevron.right"
        case "core/latest-comments": "bubble.left.and.bubble.right"
        case "core/latest-posts": "doc.plaintext"
        case "core/page-list": "list.bullet.rectangle"
        case "core/rss": "dot.radiowaves.left.and.right"
        case "core/search": "magnifyingglass"
        case "core/shortcode": "curlybraces.square"
        case "core/social-links": "person.2.circle"
        case "core/tag-cloud": "tag.circle"
            
        // MARK: - Core Theme Blocks
        case "core/site-logo": "seal"
        case "core/site-title": "textformat.size"
        case "core/site-tagline": "text.bubble"
        case "core/query": "square.grid.2x2"
        case "core/post-title": "doc.text"
        case "core/post-content": "doc.richtext"
        case "core/post-excerpt": "doc.append"
        case "core/post-featured-image": "photo"
        case "core/post-date": "calendar"
        case "core/post-author": "person.circle"
        case "core/post-comments": "bubble.left"
        case "core/post-navigation-link": "arrow.left.arrow.right"
            
        // MARK: - Core Embed Blocks
        case let name where name.hasPrefix("core-embed/"): "link.circle"
            
        // MARK: - Jetpack AI & Content
        case "jetpack/ai-assistant": "sparkles"
        case "jetpack/ai-search": "magnifyingglass.circle"
        case "jetpack/markdown": "m.square"
        case "jetpack/writing-prompt": "pencil.and.outline"
            
        // MARK: - Jetpack Contact & Forms
        case "jetpack/contact-form": "envelope"
        case "jetpack/field-text": "textformat"
        case "jetpack/field-textarea": "text.alignleft"
        case "jetpack/field-email": "envelope"
        case "jetpack/field-name": "person"
        case "jetpack/field-url": "link"
        case "jetpack/field-date": "calendar"
        case "jetpack/field-telephone": "phone"
        case "jetpack/field-checkbox": "checkmark.square"
        case "jetpack/field-checkbox-multiple": "checklist"
        case "jetpack/field-radio": "circle.circle"
        case "jetpack/field-select": "list.bullet.rectangle"
            
        // MARK: - Jetpack Media & Galleries
        case "jetpack/image-compare": "arrow.left.and.right"
        case "jetpack/tiled-gallery": "square.grid.3x3"
        case "jetpack/slideshow": "play.rectangle"
        case "jetpack/story": "book.pages"
        case "jetpack/gif": "sparkles.rectangle.stack"
            
        // MARK: - Jetpack Social & Embeds
        case "jetpack/instagram-gallery": "camera.fill"
        case "jetpack/pinterest": "pin.circle"
        case "jetpack/eventbrite": "ticket"
        case "jetpack/google-calendar": "calendar.badge.clock"
        case "jetpack/podcast-player": "mic.circle"
        case "jetpack/map": "map"
            
        // MARK: - Jetpack Business & Contact
        case "jetpack/business-hours": "clock"
        case "jetpack/contact-info": "info.circle"
        case "jetpack/address": "location"
        case "jetpack/email": "envelope"
        case "jetpack/phone": "phone"
            
        // MARK: - Jetpack Payments & E-commerce
        case "jetpack/recurring-payments": "arrow.clockwise.circle"
        case "jetpack/payment-buttons": "creditcard.circle"
        case "jetpack/donations": "heart.circle"
        case "jetpack/paywall": "lock.rectangle"
        case "jetpack/paid-content": "dollarsign.circle"
            
        // MARK: - Jetpack Marketing & Growth
        case "jetpack/subscriptions": "envelope.badge"
        case "jetpack/subscriber-login": "person.badge.key"
        case "jetpack/mailchimp": "envelope.open"
        case "jetpack/sharing-buttons": "square.and.arrow.up"
        case "jetpack/whatsapp-button": "message.circle.fill"
        case "jetpack/related-posts": "doc.on.doc"
            
        // MARK: - Jetpack Widgets & Tools
        case "jetpack/rating-star": "star.fill"
        case "jetpack/repeat-visitor": "person.2"
        case "jetpack/cookie-consent": "shield.checkered"
        case "jetpack/top-posts": "chart.bar.fill"
        case "jetpack/blog-stats": "chart.line.uptrend.xyaxis"
        case "jetpack/like": "heart"
        case "jetpack/blogroll": "list.bullet.rectangle"
            
        // MARK: - Jetpack Booking & Reservations
        case "jetpack/calendly": "calendar.badge.plus"
        case "jetpack/opentable": "fork.knife"
        case "jetpack/tock": "clock.badge.checkmark"
            
        // MARK: - Jetpack Advertising
        case "jetpack/ad": "rectangle.badge.plus"
        case "jetpack/ads": "rectangle.stack.badge.plus"
            
        // MARK: - Jetpack External Services
        case "jetpack/revue": "newspaper"
        case "jetpack/goodreads": "books.vertical"
        case "jetpack/loom": "video.bubble"
        case "jetpack/descript": "waveform.circle"
        case "jetpack/nextdoor": "house.lodge"
            
        // MARK: - Default
        default: "square"
        }
    }
}
