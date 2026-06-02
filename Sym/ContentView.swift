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

    private var canCreateLinks: Bool {
        !sources.isEmpty && destinationFolder != nil && validations.allSatisfy(\.isValid)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header

            HStack(spacing: 16) {
                DropZone(
                    title: "Source",
                    subtitle: "Drop one or more files or folders",
                    icon: .source,
                    acceptedTypes: [.fileURL],
                    onDrop: addSources
                ) {
                    SourceDropPreview(sources: sources)
                }

                DropZone(
                    title: "Link",
                    subtitle: "Drop the folder where links will be created",
                    icon: .link,
                    acceptedTypes: [.fileURL],
                    onDrop: setDestinationFolder
                ) {
                    DestinationDropPreview(destinationFolder: destinationFolder)
                }
            }
            .frame(minHeight: 218)

            sourceList

            HStack {
                Button("Clear") {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        sources.removeAll()
                        destinationFolder = nil
                        resultMessage = nil
                        errorMessage = nil
                    }
                }
                .disabled(sources.isEmpty && destinationFolder == nil)

                Spacer()

                Button("Create Link") {
                    createLinks()
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .disabled(!canCreateLinks)
            }

            statusView
        }
        .padding(28)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color.accentColor.opacity(0.055)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: sources)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: destinationFolder)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sym")
                .font(.largeTitle.weight(.semibold))
            Text("Create symbolic links from dropped sources into a selected folder.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var sourceList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sources")
                    .font(.headline)

                if !sources.isEmpty {
                    Text("\(sources.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.quaternary.opacity(0.75), in: Capsule())
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }

            if sources.isEmpty {
                EmptySourceList()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(validations) { validation in
                            SourceRow(validation: validation) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                    sources.removeAll { $0.id == validation.id }
                                    resultMessage = nil
                                    errorMessage = nil
                                }
                            }
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity.combined(with: .scale(scale: 0.96))
                            ))
                        }
                    }
                    .padding(2)
                }
                .frame(minHeight: 156, maxHeight: 240)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        if let errorMessage {
            Text(errorMessage)
                .foregroundStyle(.red)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else if let resultMessage {
            Text(resultMessage)
                .foregroundStyle(.green)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else if !sources.isEmpty && destinationFolder == nil {
            Text("Choose a Link destination folder before creating links.")
                .foregroundStyle(.secondary)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else if let invalid = validations.first(where: { !$0.isValid }) {
            Text(invalid.message ?? "Resolve highlighted sources before creating links.")
                .foregroundStyle(.red)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private func addSources(_ providers: [NSItemProvider]) -> Bool {
        loadFileURLs(from: providers) { urls in
            let newItems = urls.map(SourceItem.init(url:))
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                sources = uniqueSources(sources + newItems)
                resultMessage = nil
                errorMessage = nil
            }
        }
        return true
    }

    private func setDestinationFolder(_ providers: [NSItemProvider]) -> Bool {
        loadFileURLs(from: providers) { urls in
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                destinationFolder = urls.first
                resultMessage = nil
                errorMessage = nil
            }
        }
        return true
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
        return items.filter { item in
            seen.insert(item.url).inserted
        }
    }

    private func createLinks() {
        do {
            let result = try symlinkService.createLinks(sources: sources, in: destinationFolder)
            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                resultMessage = "Created \(result.created.count) link\(result.created.count == 1 ? "" : "s")."
                errorMessage = nil
            }
        } catch {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                resultMessage = nil
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct DropZone<Accessory: View>: View {
    let title: String
    let subtitle: String
    let icon: DropZoneIcon
    let acceptedTypes: [UTType]
    let onDrop: ([NSItemProvider]) -> Bool
    @ViewBuilder let accessory: Accessory

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                DropZoneIconView(icon: icon)
                    .frame(width: 42, height: 42)
                    .background(
                        Circle()
                            .fill(isTargeted ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.07))
                    )
                    .scaleEffect(isTargeted ? 1.08 : 1)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }
            }

            accessory
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isTargeted ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.055))
                .shadow(color: isTargeted ? Color.accentColor.opacity(0.2) : .clear, radius: 14, y: 7)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.14),
                    lineWidth: isTargeted ? 2 : 1
                )
        }
        .scaleEffect(isTargeted ? 1.015 : 1)
        .animation(.spring(response: 0.26, dampingFraction: 0.78), value: isTargeted)
        .onDrop(of: acceptedTypes, isTargeted: $isTargeted, perform: onDrop)
    }
}

private struct SourceDropPreview: View {
    let sources: [SourceItem]

    var body: some View {
        if sources.isEmpty {
            DropPrompt(text: "No sources selected")
        } else {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(sources.prefix(4))) { source in
                    MiniSourceRow(source: source)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if sources.count > 4 {
                    Text("+ \(sources.count - 4) more")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.top, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DestinationDropPreview: View {
    let destinationFolder: URL?

    var body: some View {
        if let destinationFolder {
            HStack(spacing: 9) {
                NativeFileIcon(url: destinationFolder, size: 22, fallback: .folder)
                Text(destinationFolder.path(percentEncoded: false))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
            .transition(.opacity.combined(with: .move(edge: .top)))
        } else {
            DropPrompt(text: "No folder selected")
        }
    }
}

private struct DropPrompt: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MiniSourceRow: View {
    let source: SourceItem

    var body: some View {
        HStack(spacing: 9) {
            NativeFileIcon(url: source.url, size: 22, fallback: isDirectory(source.url) ? .folder : .file)

            VStack(alignment: .leading, spacing: 1) {
                Text(source.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(source.url.deletingLastPathComponent().path(percentEncoded: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct EmptySourceList: View {
    var body: some View {
        VStack(spacing: 8) {
            NativeFileIcon(url: nil, size: 30, fallback: .folder)
                .opacity(0.72)
            Text("Drop files or folders into Source to begin.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .center)
        .background(Color.secondary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.secondary.opacity(0.12))
        }
    }
}

private struct SourceRow: View {
    let validation: SourceValidation
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                NativeFileIcon(url: validation.source.url, size: 34, fallback: isDirectory(validation.source.url) ? .folder : .file)
                    .frame(width: 38, height: 38)
                    .background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))

                Image(systemName: validation.isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(validation.isValid ? .green : .red)
                    .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(validation.source.name)
                    .font(.body.weight(.medium))
                Text(validation.proposedLinkURL?.path(percentEncoded: false) ?? validation.source.url.path(percentEncoded: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let message = validation.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Remove source")
        }
        .padding(12)
        .background(validation.isValid ? Color.secondary.opacity(0.055) : Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(validation.isValid ? Color.secondary.opacity(0.1) : Color.red.opacity(0.24))
        }
    }
}

private enum DropZoneIcon {
    case source
    case link
}

private struct DropZoneIconView: View {
    let icon: DropZoneIcon

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            NativeFileIcon(url: nil, size: 30, fallback: .folder)

            Image(systemName: icon == .source ? "plus.circle.fill" : "link.circle.fill")
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
                .offset(x: 2, y: 2)
        }
    }
}

private struct NativeFileIcon: View {
    enum Fallback {
        case file
        case folder
    }

    let url: URL?
    let size: CGFloat
    let fallback: Fallback

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }

    private var icon: NSImage {
        if let url {
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
        lock.withLock {
            collectedURLs.append(url)
        }
    }
}
