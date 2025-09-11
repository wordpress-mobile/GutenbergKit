import Testing
import GutenbergKit
import GutenbergKitAssetManifestParser

class GutenbergKitAssetManifestParserTestsTest {

    let parser = GutenbergKitAssetManifestParser()

    @Test func testScriptParsing() async throws {
        let urls = try parser.extractScriptURLs(from: #"<script type="text/javascript" src="http://localhost/wp-includes/js/dist/primitives.min.js?ver=aef2543ab60c8c9bb609" id="wp-primitives-js"></script><script type="text/javascript" src='http://localhost/wp-includes/js/dist/primitives.min.js?ver=aef2543ab60c8c9bb609' id="wp-primitives-js"></script>"\n<script src="http://localhost/wp-includes/js/dist/primitives.min.js?ver=aef2543ab60c8c9bb609"></script>"#)

        #expect(urls.count == 3)

        for url in urls {
            #expect(url == "http://localhost/wp-includes/js/dist/primitives.min.js?ver=aef2543ab60c8c9bb609")
        }
    }

    @Test func testStyleParsing() async throws {
        let urls = try parser.extractStyleURLs(from: #"<link rel='stylesheet' id='wp-components-css' href="http://localhost/wp-includes/css/dist/components/style.min.css?ver=6.7.2" type='text/css' media='all' />\n<link rel='stylesheet' id='wp-components-css' href='http://localhost/wp-includes/css/dist/components/style.min.css?ver=6.7.2' type='text/css' media='all' />\n<link href='http://localhost/wp-includes/css/dist/components/style.min.css?ver=6.7.2' rel='stylesheet' type='text/css' media='all' />"#)

        #expect(urls.count == 3)

        for url in urls {
            #expect(url == "http://localhost/wp-includes/css/dist/components/style.min.css?ver=6.7.2")
        }
    }
}
