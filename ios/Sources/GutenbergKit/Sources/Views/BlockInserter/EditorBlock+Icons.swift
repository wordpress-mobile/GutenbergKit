import Foundation

extension EditorBlock {
    /// Returns the SF Symbol icon name for the block type
    var iconName: String {
        switch name {
        // MARK: - Core Text Blocks
        case "core/paragraph": "paragraphsign"
        case "core/heading": "bookmark.fill"
        case "core/list": "list.bullet"
        case "core/list-item": "list.bullet.indent"
        case "core/details": "text.line.first.and.arrowtriangle.forward"
        case "core/quote": "quote.opening"
        case "core/code": "curlybraces"
        case "core/preformatted": "text.word.spacing"
        case "core/pullquote": "quote.bubble"
        case "core/verse": "text.quote"
        case "core/table": "tablecells"
        case "core/footnotes": "list.number"
        case "core/missing": "exclamationmark.triangle"

        // MARK: - Core Media Blocks
        case "core/image": "photo"
        case "core/gallery": "photo.stack"
        case "core/audio": "speaker.wave.2"
        case "core/cover": "photo.tv"
        case "core/file": "doc.text"
        case "core/media-text": "rectangle.split.2x1"
        case "core/video": "video"
            
        // MARK: - Core Design Blocks
        case "core/button": "rectangle.fill"
        case "core/buttons": "rectangle.3.group"
        case "core/column": "rectangle.ratio.9.to.16"
        case "core/columns": "rectangle.split.3x1"
        case "core/group": "square.on.square"
        case "core/more": "ellipsis"
        case "core/nextpage": "arrow.right.doc.on.clipboard"
        case "core/separator": "minus"
        case "core/spacer": "arrow.up.and.down"
        case "core/text-columns": "text.justify.left"
            
        // MARK: - Core Widget Blocks
        case "core/archives": "archivebox"
        case "core/calendar": "calendar"
        case "core/categories": "folder"
        case "core/html": "chevron.left.forwardslash.chevron.right"
        case "core/latest-comments": "bubble.left.and.bubble.right"
        case "core/latest-posts": "doc.plaintext"
        case "core/page-list": "list.bullet.rectangle"
        case "core/page-list-item": "doc.text"
        case "core/rss": "dot.radiowaves.left.and.right"
        case "core/search": "magnifyingglass"
        case "core/shortcode": "curlybraces.square"
        case "core/social-link": "link.circle"
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
        case "core/post-featured-image": "photo.circle"
        case "core/post-date": "calendar"
        case "core/post-author": "person.circle"
        case "core/post-comments": "bubble.left"
        case "core/post-navigation-link": "arrow.left.arrow.right"
        case "core/post-author-name": "person.text.rectangle"
        case "core/post-author-biography": "person.crop.square.filled.and.at.rectangle"
        case "core/post-comments-count": "bubble.left.and.text.bubble.right"
        case "core/post-comments-link": "bubble.left.and.bubble.right"
        case "core/post-comments-form": "text.bubble"
        case "core/post-terms": "tag"
        case "core/post-template": "doc.on.doc"
        case "core/avatar": "person.crop.circle"
        case "core/navigation": "line.3.horizontal"
        case "core/navigation-link": "link"
        case "core/navigation-submenu": "chevron.down.square"
        case "core/template-part": "square.split.2x2"
        case "core/pattern": "square.grid.3x3.square"
        case "core/block": "arrow.triangle.2.circlepath"
        case "core/home-link": "house"
        case "core/loginout": "person.crop.circle.badge.checkmark"
        case "core/term-description": "text.book.closed"
        case "core/query-title": "text.badge.checkmark"
        case "core/query-pagination": "ellipsis.rectangle"
        case "core/query-pagination-next": "chevron.right.square"
        case "core/query-pagination-numbers": "number.square"
        case "core/query-pagination-previous": "chevron.left.square"
        case "core/query-no-results": "xmark.square"
        case "core/query-total": "number.circle"
        case "core/read-more": "arrow.right.circle"
        case "core/comments": "bubble.left.and.bubble.right"
        case "core/comment-author-name": "person.bubble"
        case "core/comment-content": "text.bubble"
        case "core/comment-date": "calendar.badge.clock"
        case "core/comment-edit-link": "pencil.circle"
        case "core/comment-reply-link": "arrowshape.turn.up.left"
        case "core/comment-template": "bubble.left.and.text.bubble.right"
        case "core/comments-title": "text.bubble.fill"
        case "core/comments-pagination": "ellipsis.bubble"
        case "core/comments-pagination-next": "chevron.right.bubble"
        case "core/comments-pagination-numbers": "number.square.fill"
        case "core/comments-pagination-previous": "chevron.left.bubble"
            
        // MARK: - Core Embed Blocks
        case "core/embed": "chevron.left.forwardslash.chevron.right"
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
        case "jetpack/tiled-gallery": "rectangle.3.group"
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
