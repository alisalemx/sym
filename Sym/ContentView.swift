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
        VStack(alignment: .leading, spacing: 20) {
            header

            HStack(spacing: 16) {
                DropZone(
                    title: "Source",
                    subtitle: "Drop one or more files or folders",
                    systemImage: "tray.and.arrow.down",
                    detail: sourceDetail,
                    acceptedTypes: [.fileURL],
                    onDrop: addSources
                )

                DropZone(
                    title: "Link",
                    subtitle: "Drop the folder where links will be created",
                    systemImage: "link",
                    detail: destinationFolder?.path(percentEncoded: false) ?? "No folder selected",
                    acceptedTypes: [.fileURL],
                    onDrop: setDestinationFolder
                )
            }

            sourceList

            HStack {
                Button("Clear") {
                    sources.removeAll()
                    destinationFolder = nil
                    resultMessage = nil
                    errorMessage = nil
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
        .padding(24)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sym")
                .font(.largeTitle.weight(.semibold))
            Text("Create symbolic links from dropped sources into a selected folder.")
                .foregroundStyle(.secondary)
        }
    }

    private var sourceDetail: String {
        switch sources.count {
        case 0:
            "No sources selected"
        case 1:
            sources[0].url.path(percentEncoded: false)
        default:
            "\(sources.count) sources selected"
        }
    }

    @ViewBuilder
    private var sourceList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sources")
                .font(.headline)

            if sources.isEmpty {
                Text("Drop files or folders into Source to begin.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(validations) { validation in
                            SourceRow(validation: validation) {
                                sources.removeAll { $0.id == validation.id }
                                resultMessage = nil
                                errorMessage = nil
                            }
                        }
                    }
                    .padding(2)
                }
                .frame(minHeight: 150, maxHeight: 220)
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        if let errorMessage {
            Text(errorMessage)
                .foregroundStyle(.red)
        } else if let resultMessage {
            Text(resultMessage)
                .foregroundStyle(.green)
        } else if !sources.isEmpty && destinationFolder == nil {
            Text("Choose a Link destination folder before creating links.")
                .foregroundStyle(.secondary)
        } else if let invalid = validations.first(where: { !$0.isValid }) {
            Text(invalid.message ?? "Resolve highlighted sources before creating links.")
                .foregroundStyle(.red)
        }
    }

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
            resultMessage = "Created \(result.created.count) link\(result.created.count == 1 ? "" : "s")."
            errorMessage = nil
        } catch {
            resultMessage = nil
            errorMessage = error.localizedDescription
        }
    }
}

private struct DropZone: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let detail: String
    let acceptedTypes: [UTType]
    let onDrop: ([NSItemProvider]) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }

            Text(detail)
                .font(.callout)
                .lineLimit(2)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
                .foregroundStyle(.tertiary)
        }
        .onDrop(of: acceptedTypes, isTargeted: nil, perform: onDrop)
    }
}

private struct SourceRow: View {
    let validation: SourceValidation
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: validation.isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(validation.isValid ? .green : .red)

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
        .padding(10)
        .background(validation.isValid ? Color.secondary.opacity(0.08) : Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
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
