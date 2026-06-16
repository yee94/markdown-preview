import XCTest
@testable import MarkdownHelpers

final class MarkdownHTMLTests: XCTestCase {
    private func firstSVGTag(in html: String) throws -> String {
        let regex = try NSRegularExpression(pattern: #"<svg\b[^>]*>"#, options: [.caseInsensitive])
        let range = NSRange(location: 0, length: (html as NSString).length)
        let match = try XCTUnwrap(regex.firstMatch(in: html, range: range))
        return (html as NSString).substring(with: match.range)
    }

    func testNativeMermaidFlowchart() throws {
        let markdown = """
        ```mermaid
        graph TD
          A[Start] --> B{Decision}
        ```
        """
        let rendered = MarkdownHTML.render(markdown: markdown, darkMode: false)
        XCTAssertTrue(rendered.containsNativeMermaid, "flowchart should render natively")
        XCTAssertTrue(rendered.html.contains("class=\"mermaid-figure native-mermaid\""))
        XCTAssertTrue(rendered.html.contains("<svg"))
        XCTAssertFalse(rendered.html.contains("https://fonts.googleapis.com"))
        let svgTag = try firstSVGTag(in: rendered.html)
        XCTAssertFalse(svgTag.contains(" width="))
        XCTAssertFalse(svgTag.contains(" height="))
        XCTAssertTrue(rendered.html.contains("preserveAspectRatio=\"xMinYMin meet\""), rendered.html)
        XCTAssertTrue(svgTag.contains("max-height:calc(min(70vh,720px) - 32px)"))
        XCTAssertTrue(svgTag.contains("width:auto"))
        XCTAssertFalse(rendered.containsMermaid, "flowchart should not need JS fallback")
    }

    func testNativeMermaidUsesCustomThemeColors() {
        let markdown = """
        ```mermaid
        graph TD
          A --> B
        ```
        """
        let rendered = MarkdownHTML.render(markdown: markdown, darkMode: false)
        // Extract just the SVG portion
        guard let svgStart = rendered.html.range(of: "<svg"),
              let svgEnd = rendered.html.range(of: "</svg>") else {
            XCTFail("No SVG found in rendered output")
            return
        }
        let svg = String(rendered.html[svgStart.lowerBound...svgEnd.upperBound])
        // CSS variables should be fully resolved inside the SVG
        XCTAssertFalse(svg.contains("var(--"), "CSS variables should be fully resolved in SVG")
        XCTAssertFalse(svg.contains("color-mix("), "color-mix() should be fully resolved in SVG")
        // Native Mermaid always uses the dark palette, even when darkMode is false.
        let lowered = svg.lowercased()
        XCTAssertTrue(lowered.contains("fill=\"#2d333b\""),
                      "node fill should use the dark palette")
        XCTAssertTrue(lowered.contains("stroke=\"#81b1db\""),
                      "node stroke should use the dark palette")
        XCTAssertFalse(svg.contains("fill=\"#666666\""),
                       "unresolved library grey fallback should not remain")
    }

    func testNativeMermaidSubgraphNodeHeightsMatch() {
        let markdown = """
        ```mermaid
        graph LR
          subgraph Before [之前]
            A --> B --> C
          end
        ```
        """
        let rendered = MarkdownHTML.render(markdown: markdown, darkMode: false)
        guard let svgStart = rendered.html.range(of: "<svg"),
              let svgEnd = rendered.html.range(of: "</svg>") else {
            XCTFail("No SVG found"); return
        }
        let svg = String(rendered.html[svgStart.lowerBound...svgEnd.upperBound])
        let rectRegex = try! NSRegularExpression(
            pattern: #"<g class="node"[\s\S]*?<rect[^>]*height=\"([^\"]+)\""#
        )
        let ns = svg as NSString
        let heights = rectRegex.matches(in: svg, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range(at: 1))
        }
        XCTAssertEqual(heights.count, 3)
        XCTAssertEqual(Set(heights).count, 1, "all node rects should share one height: \(heights)")
    }

    func testNativeMermaidNoColorMixResidue() {
        // Regression: BeautifulMermaid's partial CSS-var resolver used to leave
        // broken strings like `#1F2328 60%, #FFFFFF))` in the SVG output.
        let markdown = """
        ```mermaid
        graph LR
          subgraph Before [之前]
            A[dispatch] --> B[resume] --> C[langfuse]
          end
        ```
        """
        let rendered = MarkdownHTML.render(markdown: markdown, darkMode: false)
        XCTAssertTrue(rendered.containsNativeMermaid)
        // Extract just the SVG portion
        guard let svgStart = rendered.html.range(of: "<svg"),
              let svgEnd = rendered.html.range(of: "</svg>") else {
            XCTFail("No SVG found"); return
        }
        let svg = String(rendered.html[svgStart.lowerBound...svgEnd.upperBound])
        XCTAssertFalse(svg.contains("var(--"),
                       "No unresolved CSS variables should remain in SVG")
        XCTAssertFalse(svg.contains("color-mix("),
                       "No color-mix() calls should remain in SVG")
        // Broken residue pattern: `#XXXXXX NN%, #YYYYYY))`
        XCTAssertFalse(svg.range(
            of: #"#[0-9A-Fa-f]{6}\s+\d+%,\s*#[0-9A-Fa-f]{6}\)\)"#,
            options: .regularExpression) != nil,
                       "No broken color-mix residue should remain in SVG")
    }

    func testFallbackMermaidGantt() {
        let markdown = """
        ```mermaid
        gantt
          title A Gantt Diagram
          dateFormat YYYY-MM-DD
          section Section
          A task :a1, 2024-01-01, 30d
        ```
        """
        let rendered = MarkdownHTML.render(markdown: markdown, darkMode: false)
        XCTAssertFalse(rendered.containsNativeMermaid, "gantt should not render natively")
        XCTAssertTrue(rendered.containsMermaid, "gantt should need JS fallback")
    }

    func testMixedMermaidDiagrams() {
        let markdown = """
        ```mermaid
        graph TD
        A --> B
        ```

        ```mermaid
        pie
          title Key Lime Pie Consumption
          "Dogs" : 60
          "Cats" : 40
        ```
        """
        let rendered = MarkdownHTML.render(markdown: markdown, darkMode: false)
        XCTAssertTrue(rendered.containsNativeMermaid, "flowchart should render natively")
        XCTAssertTrue(rendered.containsMermaid, "pie chart should need JS fallback")
    }

}
