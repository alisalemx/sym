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

    private var showsFooter: Bool {
        !sources.isEmpty || destinationFolder != nil || resultMessage != nil || errorMessage != nil
    }

    var body: some View {
        // Top: a band the height of the titlebar, with "Sym" centered in it (this
        // is left untouched). Sides/bottom: their own smaller inset.
        GeometryReader { proxy in
            let titlebarHeight = max(proxy.safeAreaInsets.top, 28)

            VStack(spacing: 0) {
                Text("Sym")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: titlebarHeight)

                VStack(alignment: .leading, spacing: 14) {
                    GlassEffectContainer(spacing: 14) {
                        VStack(spacing: 14) {
                            SourceSurface(
                                validations: validations,
                                invalidCount: invalidCount,
                                onDrop: addSources,
                                onChoose: chooseSources,
                                onRemove: removeSource
                            )

                            // Step 2 — revealed once at least one source is added.
                            if !sources.isEmpty {
                                LinkBar(
                                    destinationFolder: destinationFolder,
                                    onDrop: setDestinationFolder,
                                    onChoose: chooseDestination,
                                    onClear: clearDestination
                                )
                                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                    // Only present once there's something to act on or report, so the
                    // empty state keeps an even gap below the card.
                    if showsFooter {
                        footer
                    }
                }
                .padding([.horizontal, .bottom], 22)
            }
            .ignoresSafeArea()
            .background(WindowBackdrop().ignoresSafeArea())
            .animation(.smooth(duration: 0.32), value: sources)
            .animation(.smooth(duration: 0.32), value: destinationFolder)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            statusLabel
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 12)

            if !sources.isEmpty || destinationFolder != nil {
                Button("Clear", role: .destructive) {
                    clearAll()
                }
                .buttonStyle(.glass)
                .transition(.opacity)
            }

            // Step 3 — the action appears once a destination is chosen.
            if destinationFolder != nil {
                Button {
                    createLinks()
                } label: {
                    Text("Create Link\(sources.count > 1 ? "s" : "")")
                        .frame(minWidth: 84)
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.glassProminent)
                .disabled(!canCreateLinks)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var statusLabel: some View {
        if let errorMessage {
            Label(errorMessage, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        } else if let resultMessage {
            Label(resultMessage, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
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

    private func chooseSources() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Choose files or folders to link."
        panel.prompt = "Add"

        guard panel.runModal() == .OK else { return }
        let newItems = panel.urls.map(SourceItem.init(url:))
        sources = uniqueSources(sources + newItems)
        resultMessage = nil
        errorMessage = nil
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = "Choose a destination folder for the links."
        panel.prompt = "Choose"

        guard panel.runModal() == .OK else { return }
        destinationFolder = panel.urls.first
        resultMessage = nil
        errorMessage = nil
    }

    private func removeSource(_ id: SourceItem.ID) {
        sources.removeAll { $0.id == id }
        resultMessage = nil
        errorMessage = nil
    }

    private func clearDestination() {
        destinationFolder = nil
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
        BackdropView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// A backdrop that also configures its host window once attached. Doing this in
/// `viewDidMoveToWindow` (rather than `updateNSView`) guarantees the window
/// exists — making it feel chromeless while keeping the visible "Sym" title.
private final class BackdropView: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .underWindowBackground
        blendingMode = .behindWindow
        state = .active
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        // `.hiddenTitleBar` already gives us a transparent, full-size-content
        // titlebar. Keep the window titled "Sym" for the OS (Window menu, Mission
        // Control) but hide the system title text — it draws left-aligned next to
        // the traffic lights, and we render our own centered "Sym" instead.
        window.title = "Sym"
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = .clear
    }
}

// MARK: - Source surface

/// The single large surface that is both the source drop target and the list of
/// dropped items. Empty, it invites a drop; filled, it shows one row per source.
private struct SourceSurface: View {
    let validations: [SourceValidation]
    let invalidCount: Int
    let onDrop: ([NSItemProvider]) -> Bool
    let onChoose: () -> Void
    let onRemove: (SourceValidation.ID) -> Void

    @State private var isTargeted = false

    private var isEmpty: Bool { validations.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .glassEffect(
            isTargeted ? .regular.tint(.accentColor.opacity(0.35)).interactive() : .regular,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .opacity(isTargeted ? 1 : 0)
        }
        .animation(.snappy(duration: 0.22), value: isTargeted)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: onDrop)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Source")
                .font(.headline)
            if !isEmpty {
                Text("\(validations.count)")
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
            if !isEmpty {
                Button(action: onChoose) {
                    Label("Add", systemImage: "plus")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .pointerStyle(.link)
                .help("Add more files or folders")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, isEmpty ? 0 : 10)
    }

    @ViewBuilder
    private var content: some View {
        if isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(validations) { validation in
                        SourceRow(validation: validation) {
                            onRemove(validation.id)
                        }
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity.combined(with: .scale(scale: 0.97))
                        ))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
            .scrollContentBackground(.hidden)
        }
    }

    private var emptyState: some View {
        Button(action: onChoose) {
            VStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(.secondary.opacity(0.12)))
                    .scaleEffect(isTargeted ? 1.12 : 1)

                VStack(spacing: 3) {
                    Text("Drop or click to add files or folders")
                        .font(.headline)
                    Text("Each one becomes a symbolic link in the Link folder.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .padding(24)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .pointerStyle(.link)
        .help("Choose files or folders")
    }
}

// MARK: - Link bar

/// The compact destination control: a single row that names the Link folder and
/// acts as its drop target. Sits below Source, the last choice before creating.
private struct LinkBar: View {
    let destinationFolder: URL?
    let onDrop: ([NSItemProvider]) -> Bool
    let onChoose: () -> Void
    let onClear: () -> Void

    @State private var isTargeted = false

    private var isFilled: Bool { destinationFolder != nil }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onChoose) {
                HStack(spacing: 12) {
                    icon
                        .frame(width: 30, height: 30)
                        .scaleEffect(isTargeted ? 1.12 : 1)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Link")
                            .font(.subheadline.weight(.semibold))
                        Text(destinationFolder?.path(percentEncoded: false) ?? "Drop or click to choose a destination folder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .pointerStyle(.link)

            if isFilled {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove Link folder")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .glassEffect(
            isTargeted ? .regular.tint(.accentColor.opacity(0.35)).interactive() : .regular,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .opacity(isTargeted ? 1 : 0)
        }
        .help(destinationFolder?.path(percentEncoded: false) ?? "")
        .animation(.snappy(duration: 0.22), value: isTargeted)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: onDrop)
    }

    @ViewBuilder
    private var icon: some View {
        if isFilled {
            NativeFileIcon(url: destinationFolder, fallback: .folder)
        } else {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(.secondary.opacity(0.12)))
        }
    }
}

// MARK: - Source list rows

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
