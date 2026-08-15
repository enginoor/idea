import SwiftUI
import OriginCheckEngine

/// A verdict shaped for display. The engine stays UI free; this layer decides
/// how a verdict is presented and which color it wears.
struct VerdictDisplay {
    let title: String
    let detail: String
    let color: Color
    let confidenceLabel: String
    let confidenceValue: Double
    let evidence: [EvidenceItem]
    let caveat: String

    static func text(_ verdict: TextVerdict) -> VerdictDisplay {
        let title: String
        let detail: String
        let color: Color
        switch verdict.kind {
        case .watermarked:
            title = "Watermark detected"
            detail = "A positive Claude watermark signal was found in the text."
            color = .green
        case .notWatermarked:
            title = "No watermark detected"
            detail = "No positive signal was found. This is not proof of human authorship."
            color = .gray
        case .insufficientInput:
            title = "Not enough text"
            detail = "The passage is shorter than the reliable threshold for a signal."
            color = .yellow
        case .notAvailable:
            title = "Detection not yet available"
            detail = "Anthropic has not released its detection API or the detection parameters."
            color = .yellow
        case .inconclusive:
            title = "Inconclusive"
            detail = "The available signals do not resolve to a clear verdict."
            color = .yellow
        }
        return VerdictDisplay(
            title: title,
            detail: detail,
            color: color,
            confidenceLabel: verdict.confidence.label.rawValue,
            confidenceValue: verdict.confidence.value,
            evidence: verdict.evidence,
            caveat: verdict.caveatText
        )
    }

    static func file(_ verdict: FileVerdict) -> VerdictDisplay {
        let title: String
        let detail: String
        let color: Color

        if verdict.manifestPresent, verdict.signatureValid == true, verdict.modifiedSinceSigning == true {
            title = "Modified after signing"
            detail = "The manifest is valid but the file no longer matches the signed content."
            color = .red
        } else if verdict.manifestPresent, verdict.signatureValid == true {
            title = "Signed, intact"
            detail = verdict.signer.map { "Signed by \($0)." } ?? "Signed by an unknown entity."
            color = .green
        } else if verdict.manifestPresent, verdict.signatureValid == false {
            title = "Signature invalid"
            detail = "The manifest exists but its signature does not verify."
            color = .yellow
        } else if verdict.manifestPresent {
            title = "Signature unverifiable"
            detail = "The manifest exists but no validation status was reported."
            color = .yellow
        } else {
            title = "No C2PA metadata"
            detail = "No provenance manifest was found in the file."
            color = .gray
        }

        return VerdictDisplay(
            title: title,
            detail: detail,
            color: color,
            confidenceLabel: verdict.confidence.label.rawValue,
            confidenceValue: verdict.confidence.value,
            evidence: verdict.evidence,
            caveat: verdict.caveatText
        )
    }
}
