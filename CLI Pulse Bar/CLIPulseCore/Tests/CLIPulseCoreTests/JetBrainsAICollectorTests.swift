#if os(macOS)
import XCTest
@testable import CLIPulseCore

final class JetBrainsAICollectorTests: XCTestCase {

    // MARK: - XML parsing

    func testParseQuotaXMLNormal() throws {
        let xml = """
        <component name="AIAssistantQuotaManager2">
          <option name="quotaInfo" value="{&quot;type&quot;:&quot;monthly&quot;,&quot;current&quot;:150,&quot;maximum&quot;:500,&quot;until&quot;:&quot;2026-05-01T00:00:00Z&quot;}"/>
          <option name="nextRefill" value="{&quot;next&quot;:&quot;2026-05-01T00:00:00Z&quot;,&quot;amount&quot;:500}"/>
        </component>
        """

        let quota = try JetBrainsAICollector.parseQuotaXML(xml)
        XCTAssertEqual(quota.type, "monthly")
        XCTAssertEqual(quota.current, 150)
        XCTAssertEqual(quota.maximum, 500)
        XCTAssertEqual(quota.until, "2026-05-01T00:00:00Z")
        XCTAssertEqual(quota.nextRefill, "2026-05-01T00:00:00Z")
    }

    func testParseQuotaXMLWithTariff() throws {
        let xml = """
        <component name="AIAssistantQuotaManager2">
          <option name="quotaInfo" value="{&quot;type&quot;:&quot;monthly&quot;,&quot;current&quot;:400,&quot;maximum&quot;:500,&quot;until&quot;:&quot;2026-05-01T00:00:00Z&quot;,&quot;tariffQuota&quot;:{&quot;available&quot;:200}}"/>
        </component>
        """

        let quota = try JetBrainsAICollector.parseQuotaXML(xml)
        XCTAssertEqual(quota.current, 400)
        XCTAssertEqual(quota.maximum, 500)
        XCTAssertEqual(quota.tariffAvailable, 200)
    }

    func testParseQuotaXMLMissingQuotaInfo() {
        let xml = """
        <component name="AIAssistantQuotaManager2">
          <option name="somethingElse" value="{}"/>
        </component>
        """
        XCTAssertThrowsError(try JetBrainsAICollector.parseQuotaXML(xml))
    }

    func testParseQuotaXMLBadJSON() {
        let xml = """
        <component name="AIAssistantQuotaManager2">
          <option name="quotaInfo" value="not-json"/>
        </component>
        """
        XCTAssertThrowsError(try JetBrainsAICollector.parseQuotaXML(xml))
    }

    // MARK: - HTML decoding

    func testHTMLDecode() {
        let input = "&quot;type&quot;:&quot;monthly&quot;"
        let expected = "\"type\":\"monthly\""
        XCTAssertEqual(JetBrainsAICollector.htmlDecode(input), expected)
    }

    func testHTMLDecodeAllEntities() {
        let input = "&amp;&lt;&gt;&quot;&#39;&#x27;"
        let expected = "&<>\"''"
        XCTAssertEqual(JetBrainsAICollector.htmlDecode(input), expected)
    }

    // MARK: - Option extraction

    func testExtractOptionValue() {
        let xml = """
        <option name="quotaInfo" value="hello-world"/>
        """
        XCTAssertEqual(JetBrainsAICollector.extractOptionValue(xml: xml, name: "quotaInfo"), "hello-world")
    }

    func testExtractOptionValueMissing() {
        let xml = """
        <option name="other" value="hello"/>
        """
        XCTAssertNil(JetBrainsAICollector.extractOptionValue(xml: xml, name: "quotaInfo"))
    }

    // MARK: - Availability

    func testCollectorKind() {
        XCTAssertEqual(JetBrainsAICollector().kind, .jetbrainsAI)
    }
}
#endif
