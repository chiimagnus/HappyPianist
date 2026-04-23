import Foundation

extension MusicXMLParserDelegate: XMLParserDelegate {
    func parser(
        _: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        state.currentElement = elementName
        state.elementText = ""
        handleStartElement(elementName, attributes: attributeDict)
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        state.elementText += string
    }

    func parser(_: XMLParser, didEndElement elementName: String, namespaceURI _: String?, qualifiedName _: String?) {
        let text = state.elementText.trimmingCharacters(in: .whitespacesAndNewlines)
        defer {
            state.currentElement = ""
            state.elementText = ""
        }
        handleEndElement(elementName, text: text)
    }

    func parserDidEndDocument(_: XMLParser) {
        state.tempoEvents = finalizeTempoEvents()
    }
}
