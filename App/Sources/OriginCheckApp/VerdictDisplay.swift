import SwiftUI
import OriginCheckEngine

extension VerdictKind {
    /// A short, human readable title for history rows and record details.
    /// The engine stays UI free, so the wording lives in this display layer.
    /// The titles mirror the Check pane so one verdict reads the same
    /// everywhere in the app.
    var historyTitle: String {
        switch self {
        case .watermarked: "Watermark detected"
        case .notWatermarked: "No watermark detected"
        case .insufficientInput: "Not enough text"
        case .notAvailable: "Detection not available"
        case .inconclusive: "Inconclusive"
        case .batchScan: "Folder scan"
        }
    }
}

/// A verdict shaped for display. The engine stays UI free; this layer decides
/// how a verdict is presented and which color and icon it wears.
struct VerdictDisplay {
    let title: String
    let detail: String
    let color: Color
    let icon: String
    let confidenceLabel: String
    let confidenceValue: Double
    let evidence: [EvidenceItem]
    let caveat: String
    /// The verified file's name, when this verdict came from a file check.
    /// Shown as a header above the card so the result is never ambiguous
    /// after a multi-file drop.
    var fileName: String?
    /// Soft style attributions (Claude-style, ChatGPT-style, Gemini-style)
    /// from the phrase pattern database. Rendered as chips on the card.
    var familyHints: [ModelFamilyHint]

    /// A one-line summary for copying to the clipboard.
    var summaryText: String {
        let base: String
        if let fileName {
            base = "\(title) - \(confidenceLabel) (\(confidenceValue.formatted(.percent.precision(.fractionLength(0))))) - \(fileName)"
        } else {
            base = "\(title) - \(confidenceLabel) (\(confidenceValue.formatted(.percent.precision(.fractionLength(0))))) - \(detail)"
        }
        if !familyHints.isEmpty {
            let families = familyHints.map { $0.family.displayName }.joined(separator: ", ")
            return "\(base) - Style hints: \(families)"
        }
        return base
    }

    static func text(_ verdict: TextVerdict) -> VerdictDisplay {
        let title: String
        let detail: String
        let color: Color
        let icon: String
        switch verdict.kind {
        case .watermarked:
            // The local analyzer is a statistical heuristic, so the positive
            // text verdict is described as a pattern, not as the watermark.
            title = "AI-typical pattern detected"
            detail = "The text's statistical shape (sentence rhythm, vocabulary, and phrasing) resembles AI-generated prose."
            color = .green
            icon = "drop.fill"
        case .notWatermarked:
            title = "No AI-typical pattern"
            detail = "The local detector found no AI-typical statistical pattern. This is not proof of human authorship."
            color = .gray
            icon = "xmark.circle"
        case .insufficientInput:
            title = "Not enough text"
            detail = "The passage is shorter than the reliable threshold for a signal."
            color = .yellow
            icon = "text.badge.minus"
        case .notAvailable:
            title = "Detection not available"
            detail = "No detection provider could produce an honest verdict."
            color = .yellow
            icon = "hourglass"
        case .inconclusive:
            title = "Inconclusive"
            detail = "The available signals do not resolve to a clear verdict."
            color = .yellow
            icon = "questionmark.circle"
        case .batchScan:
            // Only reachable if a text verdict is ever built with the batch
            // kind; folder scans render through the batch report card.
            title = "Folder scan"
            detail = "A folder scan summary, not a single-file verdict."
            color = .gray
            icon = "folder"
        }
        return VerdictDisplay(
            title: title,
            detail: detail,
            color: color,
            icon: icon,
            confidenceLabel: verdict.confidence.label.rawValue,
            confidenceValue: verdict.confidence.value,
            evidence: verdict.evidence,
            caveat: verdict.caveatText,
            familyHints: verdict.familyHints
        )
    }

    static func file(_ verdict: FileVerdict) -> VerdictDisplay {
        let title: String
        let detail: String
        let color: Color
        let icon: String

        if verdict.manifestPresent, verdict.signatureValid == true, verdict.modifiedSinceSigning == true {
            title = "Modified after signing"
            detail = "The manifest is valid but the file no longer matches the signed content."
            color = .red
            icon = "exclamationmark.triangle.fill"
        } else if verdict.manifestPresent, verdict.signatureValid == true {
            title = "Signed, intact"
            detail = verdict.signer.map { "Signed by \($0)." } ?? "Signed by an unknown entity."
            color = .green
            icon = "checkmark.seal.fill"
        } else if verdict.manifestPresent, verdict.signatureValid == false {
            title = "Signature invalid"
            detail = "The manifest exists but its signature does not verify."
            color = .yellow
            icon = "xmark.seal.fill"
        } else if verdict.manifestPresent {
            title = "Signature unverifiable"
            detail = "The manifest exists but no validation status was reported."
            color = .yellow
            icon = "questionmark.seal"
        } else {
            title = "No C2PA metadata"
            detail = "No provenance manifest was found in the file."
            color = .gray
            icon = "doc.text.magnifyingglass"
        }

        return VerdictDisplay(
            title: title,
            detail: detail,
            color: color,
            icon: icon,
            confidenceLabel: verdict.confidence.label.rawValue,
            confidenceValue: verdict.confidence.value,
            evidence: verdict.evidence,
            caveat: verdict.caveatText,
            fileName: verdict.fileName,
            familyHints: []
        )
    }
}
