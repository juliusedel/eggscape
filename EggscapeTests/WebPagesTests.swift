@testable import Eggscape
import Foundation
import Testing

/// The privacy policy and support pages the settings link to (`WebPages`).
struct WebPagesTests {
    @Test func everyPageIsAnHTTPSPageOfTheProjectSite() throws {
        for page in WebPages.Page.allCases {
            for language in WebPages.Language.allCases {
                let url = try #require(WebPages.url(of: page, in: language))
                #expect(url.scheme == "https")
                #expect(url.host() == "juliusedel.github.io")
                #expect(url.path().hasPrefix("/eggscape/"))
                #expect(url.absoluteString == WebPages.address(of: page, in: language))
            }
        }
    }

    /// App Store Connect, the store metadata and the site itself use the same addresses.
    @Test func pagesKeepTheirPublishedAddresses() {
        let site = "https://juliusedel.github.io/eggscape/"
        #expect(WebPages.address(of: .privacyPolicy, in: .german) == site + "de/datenschutz/")
        #expect(WebPages.address(of: .privacyPolicy, in: .english) == site + "en/privacy/")
        #expect(WebPages.address(of: .support, in: .german) == site + "de/support/")
        #expect(WebPages.address(of: .support, in: .english) == site + "en/support/")
    }

    @Test func aGermanAppLinksTheGermanPagesAnyOtherLanguageTheEnglishOnes() {
        #expect(WebPages.Language(appLanguage: "de") == .german)
        #expect(WebPages.Language(appLanguage: "de-CH") == .german)
        #expect(WebPages.Language(appLanguage: "en") == .english)
        #expect(WebPages.Language(appLanguage: "fr") == .english)
        #expect(WebPages.Language(appLanguage: nil) == .english)
    }

    @Test func theAppsOwnLanguagePicksThePages() {
        let german = Bundle.main.preferredLocalizations.first == "de"
        #expect(WebPages.Language.current == (german ? .german : .english))
    }
}
