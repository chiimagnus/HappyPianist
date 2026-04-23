import Foundation

enum MusicXMLTimewiseConverterError: Error, Equatable {
    case invalidXML
    case unsupportedRootElement
}

struct MusicXMLTimewiseConverter {
    func convertToPartwiseIfNeeded(data: Data) throws -> Data {
        let root = detectRootElementName(in: data)
        switch root {
        case "score-partwise":
            return data
        case "score-timewise":
            return try convertTimewiseToPartwise(data: data)
        case nil:
            throw MusicXMLTimewiseConverterError.invalidXML
        default:
            throw MusicXMLTimewiseConverterError.unsupportedRootElement
        }
    }

    private func detectRootElementName(in data: Data) -> String? {
        guard let prefix = String(data: data.prefix(2048), encoding: .utf8) else { return nil }

        if let match = prefix.range(of: "<score-partwise") {
            _ = match
            return "score-partwise"
        }
        if let match = prefix.range(of: "<score-timewise") {
            _ = match
            return "score-timewise"
        }
        return nil
    }

    private func convertTimewiseToPartwise(data: Data) throws -> Data {
        let delegate = MusicXMLTimewiseParsingDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw MusicXMLTimewiseConverterError.invalidXML
        }

        let scoreVersionAttribute = delegate.scoreVersion.map { " version=\"\($0)\"" } ?? ""
        var output = """
        <?xml version="1.0" encoding="UTF-8"?>
        <score-partwise\(scoreVersionAttribute)>
        """

        if let partListXML = delegate.partListXML {
            output += partListXML
        }

        for partID in delegate.orderedPartIDs {
            output += "<part id=\"\(escapeAttribute(partID))\">"
            for measure in delegate.measures {
                guard let measureXML = measure.partIDToInnerXML[partID] else { continue }
                let measureNumberAttribute = " number=\"\(escapeAttribute(measure.numberToken))\""
                output += "<measure\(measureNumberAttribute)>\(measureXML)</measure>"
            }
            output += "</part>"
        }

        output += "</score-partwise>"
        return Data(output.utf8)
    }

    private func escapeAttribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

private struct TimewiseMeasure {
    let numberToken: String
    var partIDToInnerXML: [String: String]
}

private final class MusicXMLTimewiseParsingDelegate: NSObject, XMLParserDelegate {
    private(set) var scoreVersion: String?
    private(set) var partListXML: String?
    private(set) var measures: [TimewiseMeasure] = []
    private(set) var orderedPartIDs: [String] = []

    private var isInsideMeasure = false
    private var currentMeasureNumberToken: String?
    private var currentPartID: String?

    private var capturingPartListDepth: Int?
    private var partListBuilder = XMLStringBuilder()

    private var capturingPartInnerXMLDepth: Int?
    private var partInnerBuilder = XMLStringBuilder()

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        if scoreVersion == nil, (elementName == "score-timewise" || qName?.hasSuffix(":score-timewise") == true) {
            scoreVersion = attributeDict["version"]
        }

        if capturingPartListDepth != nil {
            capturingPartListDepth! += 1
            partListBuilder.startElement(elementName, attributes: attributeDict)
            return
        }

        if elementName == "part-list" || qName?.hasSuffix(":part-list") == true {
            capturingPartListDepth = 1
            partListBuilder.startElement(elementName, attributes: attributeDict)
            return
        }

        if elementName == "measure" || qName?.hasSuffix(":measure") == true {
            isInsideMeasure = true
            currentMeasureNumberToken = attributeDict["number"] ?? "\(measures.count + 1)"
            measures.append(TimewiseMeasure(numberToken: currentMeasureNumberToken ?? "\(measures.count)", partIDToInnerXML: [:]))
            return
        }

        if isInsideMeasure, let currentMeasureNumberToken, (elementName == "part" || qName?.hasSuffix(":part") == true) {
            _ = currentMeasureNumberToken
            currentPartID = attributeDict["id"] ?? ""
            if let currentPartID, !currentPartID.isEmpty, !orderedPartIDs.contains(currentPartID) {
                orderedPartIDs.append(currentPartID)
            }
            capturingPartInnerXMLDepth = 0
            partInnerBuilder = XMLStringBuilder()
            return
        }

        if capturingPartInnerXMLDepth != nil {
            capturingPartInnerXMLDepth! += 1
            partInnerBuilder.startElement(elementName, attributes: attributeDict)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturingPartListDepth != nil {
            partListBuilder.characters(string)
            return
        }
        if capturingPartInnerXMLDepth != nil {
            partInnerBuilder.characters(string)
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "measure" || qName?.hasSuffix(":measure") == true {
            isInsideMeasure = false
            currentMeasureNumberToken = nil
        }

        if capturingPartListDepth != nil {
            partListBuilder.endElement(elementName)
            capturingPartListDepth! -= 1
            if capturingPartListDepth == 0 {
                partListXML = partListBuilder.finish()
                capturingPartListDepth = nil
            }
            return
        }

        if capturingPartInnerXMLDepth != nil {
            if capturingPartInnerXMLDepth! > 0 {
                partInnerBuilder.endElement(elementName)
                capturingPartInnerXMLDepth! -= 1
                return
            }

            let innerXML = partInnerBuilder.finish()
            if let currentPartID, let measureIndex = measures.indices.last {
                measures[measureIndex].partIDToInnerXML[currentPartID] = innerXML
            }
            currentPartID = nil
            capturingPartInnerXMLDepth = nil
            return
        }
    }
}

private struct XMLStringBuilder {
    private var output = ""

    mutating func startElement(_ name: String, attributes: [String: String]) {
        output += "<\(name)"
        for (key, value) in attributes {
            output += " \(key)=\"\(escapeAttribute(value))\""
        }
        output += ">"
    }

    mutating func endElement(_ name: String) {
        output += "</\(name)>"
    }

    mutating func characters(_ text: String) {
        output += escapeText(text)
    }

    mutating func finish() -> String {
        let finished = output
        output = ""
        return finished
    }

    private func escapeText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func escapeAttribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
