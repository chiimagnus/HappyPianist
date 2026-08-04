import Foundation


extension MusicXMLParserDelegate: XMLParserDelegate {
    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard abortIfCancelled(parser) == false else { return }
        state.currentElement = elementName
        state.elementText = ""
        handleStartElement(elementName, attributes: attributeDict)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard abortIfCancelled(parser) == false else { return }
        state.elementText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI _: String?, qualifiedName _: String?) {
        guard abortIfCancelled(parser) == false else { return }
        let text = state.elementText.trimmingCharacters(in: .whitespacesAndNewlines)
        defer {
            state.currentElement = ""
            state.elementText = ""
        }
        handleEndElement(elementName, text: text)
    }

    func parserDidEndDocument(_ parser: XMLParser) {
        guard abortIfCancelled(parser) == false else { return }
        state.tempoEvents = finalizeTempoEvents()
    }
}
