import AppKit
import SwiftUI
import WebKit

enum AnnotationTool: String, CaseIterable {
    case cursor
    case pen
    case highlight
    case rectangle
    case arrow
    case text

    var label: String {
        switch self {
        case .cursor: return "Cursor"
        case .pen: return "Pen"
        case .highlight: return "Highlight"
        case .rectangle: return "Rectangle"
        case .arrow: return "Arrow"
        case .text: return "Text"
        }
    }

    var icon: String {
        switch self {
        case .cursor: return "cursorarrow"
        case .pen: return "pencil"
        case .highlight: return "highlighter"
        case .rectangle: return "rectangle"
        case .arrow: return "arrow.up.right"
        case .text: return "textformat"
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
    @Published var elementLabel = ""
    @Published var elementSelector = ""
    @Published var note = ""
    @Published var marks: [AnnotationStroke] = []
    @Published var tool: AnnotationTool = .cursor
    @Published var commenting = false
    private weak var web: WKWebView?
    private var pickerTimer: Timer?
    private var pickerRequestInFlight = false

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

    func beginComment() { commenting = true }
    func endComment() { commenting = false }

    func selectTool(_ tool: AnnotationTool) {
        self.tool = tool
        if tool == .cursor, let web { installPicker(on: web) }
        else { pickerTimer?.invalidate(); pickerTimer = nil; web?.evaluateJavaScript(Self.removePickerScript) }
    }

    func commentText() -> String {
        "BYTE ANNOTATION COMMENT\nPAGE: \(title)\nURL: \(address)\nELEMENT: \(elementLabel)\nSELECTOR: \(elementSelector)\nSELECTED TEXT:\n\(selectedText)\nNOTE:\n\(note)\n"
    }

    func installPicker(on web: WKWebView) {
        self.web = web
        web.evaluateJavaScript(Self.installPickerScript)
        pickerTimer?.invalidate()
        pickerTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self, weak web] _ in
            guard let self, !self.pickerRequestInFlight else { return }
            self.pickerRequestInFlight = true
            guard let web else { self.pickerRequestInFlight = false; return }
            web.evaluateJavaScript("window.__byteAnnotationPick || null") { value, _ in
                Task { @MainActor in
                    self.pickerRequestInFlight = false
                    guard let result = value as? [String: Any], !result.isEmpty else { return }
                    self.elementLabel = result["label"] as? String ?? ""
                    self.elementSelector = result["selector"] as? String ?? ""
                    self.selectedText = result["text"] as? String ?? ""
                    self.stopPicker()
                }
            }
        }
    }

    func stopPicker() {
        pickerTimer?.invalidate()
        pickerTimer = nil
        web?.evaluateJavaScript(Self.removePickerScript)
    }

    static let installPickerScript = """
    (() => {
      if (window.__byteAnnotationPicker) return "ready";
      const state = { current: null, outline: "", pick: null };
      const overlay = document.createElement("div");
      overlay.id = "byte-annotation-picker";
      Object.assign(overlay.style, { position: "fixed", inset: "0", zIndex: "2147483646", pointerEvents: "none" });
      const label = document.createElement("div");
      Object.assign(label.style, { position: "fixed", display: "none", padding: "2px 5px", borderRadius: "3px", background: "#2477e8", color: "white", font: "600 12px -apple-system,BlinkMacSystemFont,sans-serif", boxShadow: "0 1px 4px #0004" });
      overlay.appendChild(label); document.documentElement.appendChild(overlay);
      function name(node) {
        const tag = node.tagName.toLowerCase();
        const classes = [...node.classList].slice(0, 2).map(c => "." + c.replace(/[^a-zA-Z0-9_-]/g, "")).join("");
        return tag + classes;
      }
      function move(event) {
        const node = document.elementFromPoint(event.clientX, event.clientY);
        if (!node || node === overlay || overlay.contains(node)) return;
        if (state.current) state.current.style.outline = state.outline;
        state.current = node; state.outline = node.style.outline;
        node.style.outline = "2px solid #2477e8";
        const rect = node.getBoundingClientRect();
        label.textContent = name(node); label.style.display = "block";
        label.style.left = Math.max(4, rect.left) + "px"; label.style.top = Math.max(4, rect.top - 22) + "px";
      }
      function click(event) {
        const node = state.current || document.elementFromPoint(event.clientX, event.clientY);
        if (!node || node === overlay || overlay.contains(node)) return;
        event.preventDefault(); event.stopPropagation();
        state.pick = { label: name(node), selector: name(node), text: (node.innerText || node.textContent || "").trim().slice(0, 1000) };
        window.__byteAnnotationPick = state.pick;
      }
      document.addEventListener("mousemove", move, true);
      document.addEventListener("click", click, true);
      window.__byteAnnotationPicker = { overlay, state, move, click };
      return "ready";
    })()
    """

    static let removePickerScript = """
    (() => { const p = window.__byteAnnotationPicker; if (!p) return "gone"; if (p.state.current) p.state.current.style.outline = p.state.outline; document.removeEventListener("mousemove", p.move, true); document.removeEventListener("click", p.click, true); p.overlay.remove(); delete window.__byteAnnotationPicker; delete window.__byteAnnotationPick; return "gone"; })()
    """

    deinit { pickerTimer?.invalidate() }

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
        annotation.installPicker(on: web)
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

    func closeAnnotation() {
        annotating?.stopPicker()
        annotating?.endComment()
        annotating = nil
    }

    func commentOnAnnotation() {
        guard let annotation = annotating, !annotation.elementLabel.isEmpty else {
            announce("Select an element first")
            return
        }
        annotation.beginComment()
    }

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
        Group {
            if annotation.commenting {
                commentCard
            } else {
                toolbar
            }
        }
    }

    private var toolbar: some View {
        VStack(spacing: 3) {
            toolButton(.cursor, help: "Pick element")
            dockButton("text.bubble", help: "Comment on selected element   C", active: annotation.commenting) {
                browser.commentOnAnnotation()
            }
            toolButton(.pen, help: "Draw")
            toolButton(.rectangle, help: "Rectangle")
            toolButton(.text, help: "Add comment")
            Divider().frame(width: 22).padding(.vertical, 2)
            dockButton("doc.on.doc", help: "Copy annotation comment") { browser.copyAnnotation() }
            dockButton("xmark", help: "Close annotation") { browser.closeAnnotation() }
        }
        .font(.system(size: 13, weight: .medium))
        .padding(7)
        .background(Color.white.opacity(0.97), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.black.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
        .accessibilityLabel(annotation.elementLabel.isEmpty ? "Annotation tools" : annotation.elementLabel)
    }

    private var commentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Leave a comment on this element…", text: $annotation.note)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            Text(annotation.elementLabel.isEmpty ? "Select an element first" : annotation.elementLabel)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 7) {
                Button("Copy") { browser.copyAnnotation(); annotation.endComment() }
                Button("ChatGPT") { browser.sendAnnotation(to: .codex) }
                Button("Claude") { browser.sendAnnotation(to: .claude) }
                Spacer()
                Button { annotation.endComment() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .frame(width: 300)
        .background(Color.white.opacity(0.98), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 16, y: 5)
    }

    private func toolButton(_ tool: AnnotationTool, help: String) -> some View {
        dockButton(tool.icon, help: help, active: annotation.tool == tool) { annotation.selectTool(tool) }
    }

    private func dockButton(_ icon: String, help: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Circle()
                    .fill(active ? Color.accentColor : .clear)
                    .frame(width: 5, height: 5)
                Image(systemName: icon)
                    .frame(width: 23, height: 24)
                    .foregroundStyle(active ? Color.accentColor : Color.black.opacity(0.72))
            }
            .frame(width: 34, height: 25)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
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
