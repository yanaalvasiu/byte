import AppKit
import SwiftUI
import WebKit

enum AnnotationTool: String, CaseIterable {
    case pen
    case highlight
    case rectangle
    case arrow

    var label: String {
        switch self {
        case .pen: return "Pen"
        case .highlight: return "Highlight"
        case .rectangle: return "Rectangle"
        case .arrow: return "Arrow"
        }
    }

    var icon: String {
        switch self {
        case .pen: return "pencil"
        case .highlight: return "highlighter"
        case .rectangle: return "rectangle"
        case .arrow: return "arrow.up.right"
        }
    }
}

struct AnnotationStroke: Identifiable {
    let id = UUID()
    let tool: AnnotationTool
    let points: [CGPoint]
}

/// A visual comment attached to the page in front.
@MainActor
final class Annotation: ObservableObject, Identifiable {
    let id = UUID()
    let tabID: Tab.ID
    let title: String
    let address: String
    @Published var screenshot: NSImage?
    @Published var selectedText = ""
    @Published var note = ""
    @Published var marks: [AnnotationStroke] = []
    @Published var tool: AnnotationTool = .pen

    init(tab: Tab) {
        tabID = tab.id
        title = tab.title
        address = tab.pageAddress?.absoluteString ?? tab.address?.absoluteString ?? ""
    }

    var imageAspectRatio: CGFloat {
        guard let screenshot, screenshot.size.height > 0 else { return 1.5 }
        return screenshot.size.width / screenshot.size.height
    }

    func add(_ stroke: AnnotationStroke) {
        guard stroke.points.count > 1 else { return }
        marks.append(stroke)
    }

    func undo() { _ = marks.popLast() }

    func commentText() -> String {
        "BYTE ANNOTATION COMMENT\nPAGE: \(title)\nURL: \(address)\nSELECTED TEXT:\n\(selectedText)\nNOTE:\n\(note)\n"
    }

    func renderedImage() -> NSImage? {
        guard let screenshot else { return nil }
        let image = NSImage(size: screenshot.size)
        image.lockFocus()
        screenshot.draw(in: NSRect(origin: .zero, size: screenshot.size))
        for mark in marks { draw(mark, in: screenshot.size) }
        image.unlockFocus()
        return image
    }

    private func draw(_ mark: AnnotationStroke, in size: NSSize) {
        guard mark.points.first != nil else { return }
        let points = mark.points.map { NSPoint(x: $0.x * size.width, y: $0.y * size.height) }
        let path = NSBezierPath()
        path.move(to: points[0])
        if mark.tool == .rectangle || mark.tool == .arrow {
            guard let last = points.last else { return }
            if mark.tool == .rectangle {
                NSColor.systemRed.setStroke()
                path.appendRect(NSRect(x: min(points[0].x, last.x), y: min(points[0].y, last.y), width: abs(last.x - points[0].x), height: abs(last.y - points[0].y)))
                path.lineWidth = 4
                path.stroke()
            } else {
                drawArrow(from: points[0], to: last)
            }
            return
        }
        for point in points.dropFirst() { path.line(to: point) }
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.lineWidth = mark.tool == .highlight ? 22 : 5
        (mark.tool == .highlight ? NSColor.systemYellow.withAlphaComponent(0.38) : NSColor.systemRed).setStroke()
        path.stroke()
    }

    private func drawArrow(from start: NSPoint, to end: NSPoint) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let head: CGFloat = 18
        let left = NSPoint(x: end.x - head * cos(angle - .pi / 6), y: end.y - head * sin(angle - .pi / 6))
        let right = NSPoint(x: end.x - head * cos(angle + .pi / 6), y: end.y - head * sin(angle + .pi / 6))
        path.move(to: left)
        path.line(to: end)
        path.line(to: right)
        path.lineWidth = 5
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        NSColor.systemRed.setStroke()
        path.stroke()
    }
}

enum AnnotationDestination { case claude, codex }

extension Browser {
    func annotatePage() {
        guard let tab = active, tab.isWeb else {
            announce("Open a web page before annotating")
            return
        }
        let web = tab.web
        let annotation = Annotation(tab: tab)
        annotating = annotation
        announce("Annotation ready")
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = true
        web.takeSnapshot(with: configuration) { image, _ in
            MainActor.assumeIsolated {
                annotation.screenshot = image
            }
        }
        web.evaluateJavaScript("window.getSelection ? window.getSelection().toString() : ''") { value, _ in
            Task { @MainActor in annotation.selectedText = value as? String ?? "" }
        }
    }

    func closeAnnotation() { annotating = nil }

    func copyAnnotation() {
        guard let annotation = annotating else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(annotation.commentText(), forType: .string)
        if let image = annotation.renderedImage(), let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            item.setData(png, forType: .png)
        }
        pasteboard.writeObjects([item])
        announce("Annotation copied as a comment")
    }

    func sendAnnotation(to destination: AnnotationDestination) {
        guard annotating != nil else { return }
        copyAnnotation()
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
        announce("Annotation copied — paste it into \(destination == .claude ? "Claude" : "Codex")")
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
                Text("Annotate comment")
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

            if annotation.screenshot != nil {
                AnnotationCanvas(annotation: annotation)
                    .frame(width: 880, height: 500)
                    .padding(.horizontal, 12)
            } else {
                ProgressView().frame(width: 880, height: 180)
            }

            HStack(spacing: 6) {
                ForEach(AnnotationTool.allCases, id: \.self) { tool in
                    Button {
                        annotation.tool = tool
                    } label: {
                        Label(tool.label, systemImage: tool.icon)
                    }
                    .buttonStyle(.bordered)
                    .tint(annotation.tool == tool ? Palette.ink : Palette.muted)
                }
                Spacer()
                Button("Undo") { annotation.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                Button("Copy comment") { browser.copyAnnotation() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.top, 10)

            TextEditor(text: $annotation.note)
                .font(.system(size: 12))
                .frame(minHeight: 54, maxHeight: 90)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(Palette.frame, in: RoundedRectangle(cornerRadius: 7))
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
        .frame(width: 920, height: 650)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
    }
}

struct AnnotationCanvas: View {
    @ObservedObject var annotation: Annotation
    @State private var current: [CGPoint] = []

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let screenshot = annotation.screenshot {
                    Image(nsImage: screenshot)
                        .resizable()
                        .aspectRatio(annotation.imageAspectRatio, contentMode: .fit)
                }
                Canvas { context, size in
                    for stroke in annotation.marks { draw(stroke, in: size, context: &context) }
                    if current.count > 1 {
                        draw(AnnotationStroke(tool: annotation.tool, points: current), in: size, context: &context)
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        current.append(CGPoint(x: value.location.x / proxy.size.width, y: value.location.y / proxy.size.height))
                    }
                    .onEnded { _ in
                        annotation.add(AnnotationStroke(tool: annotation.tool, points: current))
                        current.removeAll(keepingCapacity: true)
                    })
            }
        }
        .aspectRatio(annotation.imageAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.hairline, lineWidth: 1))
    }

    private func draw(_ stroke: AnnotationStroke, in size: CGSize, context: inout GraphicsContext) {
        guard let first = stroke.points.first else { return }
        let points = stroke.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        var path = Path()
        path.move(to: points[0])
        if stroke.tool == .rectangle, let last = points.last {
            path.addRect(CGRect(x: min(first.x * size.width, last.x), y: min(first.y * size.height, last.y), width: abs(last.x - first.x * size.width), height: abs(last.y - first.y * size.height)))
        } else {
            for point in points.dropFirst() { path.addLine(to: point) }
        }
        let color: Color = stroke.tool == .highlight ? .yellow.opacity(0.38) : .red
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: stroke.tool == .highlight ? 18 : 3, lineCap: .round, lineJoin: .round))
        if stroke.tool == .arrow, let last = points.last {
            let angle = atan2(last.y - points[0].y, last.x - points[0].x)
            var head = Path()
            head.move(to: last)
            head.addLine(to: CGPoint(x: last.x - 16 * cos(angle - .pi / 6), y: last.y - 16 * sin(angle - .pi / 6)))
            head.move(to: last)
            head.addLine(to: CGPoint(x: last.x - 16 * cos(angle + .pi / 6), y: last.y - 16 * sin(angle + .pi / 6)))
            context.stroke(head, with: .color(.red), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
    }
}
