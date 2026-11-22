# Byte

Byte is a focused macOS browser for testing the things you build.

It is based on the open-source Search browser and keeps its WebKit foundation, developer tools, page controls, and fast tab workflow while making the default surface intentionally quiet:

- no permanent address bar or tab sidebar
- `⌘S` summons the search/address field
- Google is the only search engine
- `⌥⌘I` opens Web Inspector
- `⌥⌘J` opens the JavaScript console
- `⌥⌘C` inspects an element
- `⇧⌘A` opens visual page annotation
- `⇧⌘1` copies annotation context for Claude
- `⇧⌘2` copies annotation context for Codex
- `Esc` closes the annotation panel

Annotation starts in element-picker mode. Move over the live page to highlight a DOM node and show its tag/class label, then click it to attach that target to the comment. The compact bottom dock keeps the cursor active in blue and exposes drawing/text tools beside it. Copying the comment places the marked image, selected element, URL, and note on the clipboard. The Claude and Codex actions do the same copy and open the selected agent, ready for you to paste the comment into your development conversation.

## Build

Requirements:

- macOS 14 or newer
- Xcode with Swift 6 or newer

From the repository root:

```sh
./build.sh
open build/Byte.app
```

The release build uses size optimization and produces an arm64 app on Apple Silicon. Set `SEARCH_ARCH=x86_64` to build an Intel variant.

## Project layout

- `Sources/Search/` — the SwiftUI/AppKit/WebKit application
- `Sources/Search/Annotation.swift` — developer annotation and assistant handoff
- `build.sh` — local macOS app packaging script
- `Tests/SearchTests/` — regression and behavior tests inherited from the Search foundation

## Privacy

Byte is intended for local development work. It does not add telemetry. Page context is only placed on the clipboard when you explicitly invoke an annotation destination.

## Status

Byte is an active personal development tool. It is not a general-purpose browser replacement.

## Development workflow

Build locally, test the exact interaction you are changing, and keep the app focused on the page under test. Releases and pushes are intentionally manual.

## License

See [LICENSE](LICENSE) for the upstream license and attribution.
