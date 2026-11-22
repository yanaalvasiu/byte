# Byte

Byte is a focused macOS browser for testing the things you build.

It is based on the open-source Search browser and keeps its WebKit foundation, developer tools, page controls, and fast tab workflow while making the default surface intentionally quiet:

- no permanent address bar or tab sidebar
- `⌘S` summons the search/address field
- Google is the only search engine
- `⌥⌘I` opens Web Inspector
- `⌥⌘J` opens the JavaScript console
- `⌥⌘C` inspects an element
- `⇧⌘A` opens page annotation
- `⇧⌘1` copies annotation context for Claude
- `⇧⌘2` copies annotation context for Codex
- `Esc` closes the annotation panel

Annotation context includes the current page, URL, selected text, and your note. Byte copies that context to the clipboard and opens the selected assistant so you can paste it into your development conversation.

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

## License

See [LICENSE](LICENSE) for the upstream license and attribution.
