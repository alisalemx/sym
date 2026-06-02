import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var sources: [SourceItem] = []
    @State private var destinationFolder: URL?
    @State private var resultMessage: String?
    @State private var errorMessage: String?

    private let symlinkService = SymlinkService()

    private var validations: [SourceValidation] {
        symlinkService.validate(sources: sources, destinationFolder: destinationFolder)
    }

    private var invalidCount: Int {
        validations.filter { !$0.isValid }.count
    }

    private var canCreateLinks: Bool {
        !sources.isEmpty && destinationFolder != nil && validations.allSatisfy(\.isValid)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                header
                dropZones
                sourceSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            footer
        }
        .background(WindowBackdrop())
        .animation(.smooth(duration: 0.32), value: sources)
        .animation(.smooth(duration: 0.32), value: destinationFolder)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sym")
                .font(.largeTitle.weight(.bold))
            Text("Drop sources and a destination folder to create symbolic links.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Drop zones

    private var dropZones: some View {
        GlassEffectContainer(spacing: 18) {
            HStack(spacing: 14) {
                DropZone(
                    title: "Source",
                    prompt: "Drop files or folders",
                    detail: sources.isEmpty ? nil : "^[\(sources.count) item](inflect: true) selected",
                    iconKind: .source,
                    isFilled: !sources.isEmpty,
                    onDrop: addSources
                )

                Image(systemName: "arrow.forward")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)

                DropZone(
                    title: "Link",
                    prompt: "Drop a destination folder",
                    detail: destinationFolder?.lastPathComponent,
                    detailHelp: destinationFolder?.path(percentEncoded: false),
                    iconKind: .link(destinationFolder),
                    isFilled: destinationFolder != nil,
                    onDrop: setDestinationFolder
                )
            }
        }
    }

    // MARK: - Source list

    @ViewBuilder
    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Sources")
                    .font(.headline)
                if !sources.isEmpty {
                    Text("\(sources.count)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Spacer()
                if invalidCount > 0 {
                    Label("^[\(invalidCount) conflict](inflect: true)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                        .labelStyle(.titleAndIcon)
                }
            }

            Group {
                if sources.isEmpty {
                    EmptySourceList()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(validations) { validation in
                                SourceRow(validation: validation) {
                                    removeSource(validation.id)
                                }
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .top)),
                                    removal: .opacity.combined(with: .scale(scale: 0.97))
                                ))
                            }
                        }
                        .padding(8)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            statusLabel
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 12)

            Button("Clear", role: .destructive) {
                clearAll()
            }
            .buttonStyle(.glass)
            .disabled(sources.isEmpty && destinationFolder == nil)

            Button {
                createLinks()
            } label: {
                Text("Create Link\(sources.count > 1 ? "s" : "")")
                    .frame(minWidth: 84)
            }
            .keyboardShortcut(.return, modifiers: [])
            .buttonStyle(.glassProminent)
            .disabled(!canCreateLinks)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        if let errorMessage {
            Label(errorMessage, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        } else if let resultMessage {
            Label(resultMessage, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if !sources.isEmpty && destinationFolder == nil {
            Label("Choose a Link folder to continue.", systemImage: "info.circle")
                .foregroundStyle(.secondary)
        } else if invalidCount > 0 {
            Label("Resolve the highlighted conflicts to continue.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else if canCreateLinks {
            Label("Ready to create ^[\(sources.count) link](inflect: true).", systemImage: "checkmark")
                .foregroundStyle(.secondary)
        } else {
            Label("Drop sources and a Link folder to begin.", systemImage: "arrow.down.to.line")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func addSources(_ providers: [NSItemProvider]) -> Bool {
        loadFileURLs(from: providers) { urls in
            let newItems = urls.map(SourceItem.init(url:))
            sources = uniqueSources(sources + newItems)
            resultMessage = nil
            errorMessage = nil
        }
        return true
    }

    private func setDestinationFolder(_ providers: [NSItemProvider]) -> Bool {
        loadFileURLs(from: providers) { urls in
            destinationFolder = urls.first
            resultMessage = nil
            errorMessage = nil
        }
        return true
    }

    private func removeSource(_ id: SourceItem.ID) {
        sources.removeAll { $0.id == id }
        resultMessage = nil
        errorMessage = nil
    }

    private func clearAll() {
        sources.removeAll()
        destinationFolder = nil
        resultMessage = nil
        errorMessage = nil
    }

    private func loadFileURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let collector = DropURLCollector()
        let group = DispatchGroup()

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }

                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    collector.append(url)
                } else if let url = item as? URL {
                    collector.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            completion(collector.urls)
        }
    }

    private func uniqueSources(_ items: [SourceItem]) -> [SourceItem] {
        var seen: Set<URL> = []
        return items.filter { seen.insert($0.url).inserted }
    }

    private func createLinks() {
        do {
            let result = try symlinkService.createLinks(sources: sources, in: destinationFolder)
            resultMessage = "Created ^[\(result.created.count) link](inflect: true)."
            errorMessage = nil
        } catch {
            resultMessage = nil
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Window backdrop

/// Lets the desktop show through the window so the Liquid Glass surfaces have
/// something to refract. Falls back to the standard window material everywhere else.
private struct WindowBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Drop zone

private enum DropZoneIconKind {
    case source
    case link(URL?)
}

private struct DropZone: View {
    let title: String
    let prompt: String
    var detail: String?
    var detailHelp: String?
    let iconKind: DropZoneIconKind
    let isFilled: Bool
    let onDrop: ([NSItemProvider]) -> Bool

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 12) {
            icon
                .frame(width: 52, height: 52)
                .scaleEffect(isTargeted ? 1.12 : 1)

            VStack(spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail ?? prompt)
                    .font(.subheadline)
                    .foregroundStyle(isFilled ? .primary : .secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 148)
        .padding(.horizontal, 12)
        .glassEffect(
            isTargeted ? .regular.tint(.accentColor.opacity(0.35)).interactive() : .regular,
            in: .rect(cornerRadius: 18)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(isFilled ? 0 : 0.35),
                    style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.5, dash: isFilled ? [] : [7, 5])
                )
                .opacity(isTargeted || !isFilled ? 1 : 0)
        }
        .help(detailHelp ?? "")
        .animation(.snappy(duration: 0.22), value: isTargeted)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: onDrop)
    }

    @ViewBuilder
    private var icon: some View {
        switch iconKind {
        case .source:
            NativeFileIcon(url: nil, fallback: .folder)
        case let .link(url):
            NativeFileIcon(url: url, fallback: .folder)
        }
    }
}

// MARK: - Source list rows

private struct EmptySourceList: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Dropped files and folders appear here.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private struct SourceRow: View {
    let validation: SourceValidation
    let onRemove: () -> Void

    @State private var isHovering = false

    private var isValid: Bool { validation.isValid }

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                NativeFileIcon(
                    url: validation.source.url,
                    fallback: isDirectory(validation.source.url) ? .folder : .file
                )
                .frame(width: 32, height: 32)

                Image(systemName: isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white, isValid ? Color.green : Color.orange)
                    .background(Circle().fill(.background))
                    .offset(x: 3, y: 3)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(validation.source.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(isValid ? Color.secondary : Color.orange)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0.35)
            .help("Remove source")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 11)
                .fill(isValid ? AnyShapeStyle(.quaternary.opacity(0.5)) : AnyShapeStyle(Color.orange.opacity(0.12)))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .strokeBorder(isValid ? Color.clear : Color.orange.opacity(0.4))
        }
        .onHover { isHovering = $0 }
    }

    private var detailText: String {
        if let message = validation.message {
            return message
        }
        return validation.proposedLinkURL?.path(percentEncoded: false)
            ?? validation.source.url.path(percentEncoded: false)
    }
}

// MARK: - Native file icon

private struct NativeFileIcon: View {
    enum Fallback {
        case file
        case folder
    }

    let url: URL?
    let fallback: Fallback

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
    }

    private var icon: NSImage {
        if let url, FileManager.default.fileExists(atPath: url.path) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: fallback == .folder ? .folder : .item)
    }
}

private func isDirectory(_ url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
}

private final class DropURLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var collectedURLs: [URL] = []

    var urls: [URL] {
        lock.withLock { collectedURLs }
    }

    func append(_ url: URL) {
        lock.withLock { collectedURLs.append(url) }
    }
}
