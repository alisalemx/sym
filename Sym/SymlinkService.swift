import Foundation

struct SourceItem: Identifiable, Hashable {
    let url: URL

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

struct SourceValidation: Identifiable, Equatable {
    let source: SourceItem
    let proposedLinkURL: URL?
    let message: String?

    var id: URL { source.url }
    var isValid: Bool { message == nil }
}

struct LinkCreationResult: Equatable {
    let created: [URL]
}

enum SymlinkValidationError: LocalizedError, Equatable {
    case noSources
    case noDestination
    case destinationIsNotFolder(URL)
    case missingSource(URL)
    case conflict(URL)
    case validationFailed(String)

    var errorDescription: String? {
        switch self {
        case .noSources:
            "Add at least one source."
        case .noDestination:
            "Choose a link destination folder."
        case let .destinationIsNotFolder(url):
            "\(url.lastPathComponent) is not a folder."
        case let .missingSource(url):
            "\(url.lastPathComponent) no longer exists."
        case let .conflict(url):
            "A link named \(url.lastPathComponent) already exists."
        case let .validationFailed(message):
            message
        }
    }
}

struct SymlinkService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func validate(sources: [SourceItem], destinationFolder: URL?) -> [SourceValidation] {
        guard let destinationFolder else {
            return sources.map {
                SourceValidation(source: $0, proposedLinkURL: nil, message: SymlinkValidationError.noDestination.localizedDescription)
            }
        }

        guard isDirectory(destinationFolder) else {
            return sources.map {
                SourceValidation(
                    source: $0,
                    proposedLinkURL: destinationFolder.appendingPathComponent($0.name),
                    message: SymlinkValidationError.destinationIsNotFolder(destinationFolder).localizedDescription
                )
            }
        }

        return sources.map { source in
            let proposedLinkURL = destinationFolder.appendingPathComponent(source.name)

            if !fileManager.fileExists(atPath: source.url.path) {
                return SourceValidation(
                    source: source,
                    proposedLinkURL: proposedLinkURL,
                    message: SymlinkValidationError.missingSource(source.url).localizedDescription
                )
            }

            if fileManager.fileExists(atPath: proposedLinkURL.path) {
                return SourceValidation(
                    source: source,
                    proposedLinkURL: proposedLinkURL,
                    message: SymlinkValidationError.conflict(proposedLinkURL).localizedDescription
                )
            }

            return SourceValidation(source: source, proposedLinkURL: proposedLinkURL, message: nil)
        }
    }

    func createLinks(sources: [SourceItem], in destinationFolder: URL?) throws -> LinkCreationResult {
        guard !sources.isEmpty else { throw SymlinkValidationError.noSources }
        guard let destinationFolder else { throw SymlinkValidationError.noDestination }
        guard isDirectory(destinationFolder) else {
            throw SymlinkValidationError.destinationIsNotFolder(destinationFolder)
        }

        let validations = validate(sources: sources, destinationFolder: destinationFolder)
        if let invalid = validations.first(where: { !$0.isValid }), let message = invalid.message {
            throw SymlinkValidationError.validationFailed(message)
        }

        var created: [URL] = []
        do {
            for source in sources {
                let linkURL = destinationFolder.appendingPathComponent(source.name)
                try fileManager.createSymbolicLink(at: linkURL, withDestinationURL: source.url.absoluteURL)
                created.append(linkURL)
            }
        } catch {
            for url in created {
                try? fileManager.removeItem(at: url)
            }
            throw error
        }

        return LinkCreationResult(created: created)
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
