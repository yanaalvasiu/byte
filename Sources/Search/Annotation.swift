import AppKit
import SwiftUI

/// A short-lived handoff from the page in front to a coding assistant.
@MainActor
final class Annotation: ObservableObject, Identifiable {
    let id = UUID()
    let tabID: Tab.ID
    let title: String
    let address: String
    @Published var selectedText = ""
    @Published var note = ""

    init(tab: Tab) {
        tabID = tab.id
        title = tab.title
        address = tab.pageAddress?.absoluteString ?? tab.address?.absoluteString ?? ""
    }
}

enum AnnotationDestination { case claude, codex }

extension Browser {
    func annotatePage() {
        guard let tab = active, tab.isWeb else {
            announce("Open a web page before annotating")
            return
        }
        let annotation = Annotation(tab: tab)
        annotating = annotation
        tab.built?.evaluateJavaScript("window.getSelection ? window.getSelection().toString() : ''") { value, _ in
            Task { @MainActor in annotation.selectedText = value as? String ?? "" }
        }
    }

    func closeAnnotation() { annotating = nil }

    func sendAnnotation(to destination: AnnotationDestination) {
        guard let annotation = annotating else { return }
        let context = "FOCUS DEVELOPER CONTEXT\nPAGE: \(annotation.title)\nURL: \(annotation.address)\nSELECTED TEXT:\n\(annotation.selectedText)\nNOTE:\n\(annotation.note)\n"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(context, forType: .string)

        let bundleID: String
        let fallback: URL
        switch destination {
        case .claude:
            bundleID = "com.anthropic.claudefordesktop"
            fallback = URL(string: "https://claude.ai/new")!
        case .codex:
            bundleID = "com.openai.codex"
            fallback = URL(string: "https://chatgpt.com/")!
        }
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.open(appURL)
        } else {
            NSWorkspace.shared.open(fallback)
        }
        closeAnnotation()
        announce("Context copied — paste it into \(destination == .claude ? "Claude" : "Codex")")
    }
}

struct AnnotationPanel: View {
    @ObservedObject var browser: Browser
    @ObservedObject var annotation: Annotation

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "highlighter")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.muted)
                Text("Annotate")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text("⇧⌘A")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Palette.muted)
                Door(icon: "xmark", help: "Close   esc") { browser.closeAnnotation() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text(annotation.title.isEmpty ? annotation.address : annotation.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                if !annotation.selectedText.isEmpty {
                    Text(annotation.selectedText)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(4)
                        .padding(8)
                        .background(Palette.wash, in: RoundedRectangle(cornerRadius: 7))
                }
                TextEditor(text: $annotation.note)
                    .font(.system(size: 12))
                    .frame(minHeight: 74)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(Palette.frame, in: RoundedRectangle(cornerRadius: 7))
            }
            .padding(14)

            HStack(spacing: 8) {
                Button("Claude  ⇧⌘1") { browser.sendAnnotation(to: .claude) }
                Button("Codex  ⇧⌘2") { browser.sendAnnotation(to: .codex) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .frame(width: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
    }
}
