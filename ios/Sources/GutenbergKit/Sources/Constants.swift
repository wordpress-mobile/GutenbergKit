import Foundation

public struct Constants {

    public struct EditorAssetLibrary {
        public static let urlScheme = "gbk-cache-https"
    }

    public struct API {
        public static let editorSettingsPath = "/wp-block-editor/v1/settings"
        public static let activeThemePath = "/wp/v2/themes?context=edit&status=active"
        public static let siteSettingsPath = "/wp/v2/settings"
        public static let postTypesPath = "/wp/v2/types?context=view"
    }
}
