import Foundation

/// Helper function to move a file to the user's Downloads directory without overwriting a file. Returns URL to new path.
/// Might change the filename to make it unique.
func moveFileToDownloadsFolder(fileURL: URL, preferredFilename: String) throws -> URL {
    // Choose destination that does not exist
    let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    let destinationURL = downloadsDirectory.appendingPathComponent(preferredFilename)
    var counter = 1
    var uniqueDestinationURL = destinationURL // URL to unique destination path e.g. "myfile-2.txt" or "myfile-3.txt"
    while FileManager.default.fileExists(atPath: uniqueDestinationURL.path) { // Make filename unique e.g. "myfile.txt" -> "myfile-2.txt" or "myfile-3.txt"
        counter += 1
        uniqueDestinationURL = destinationURL.deletingLastPathComponent().appendingPathComponent("\(destinationURL.deletingPathExtension().lastPathComponent)-\(counter).\(destinationURL.pathExtension)")
    }
    // Save the file to the Downloads folder
    do {
        try FileManager.default.moveItem(at: fileURL, to: uniqueDestinationURL)
    } catch { return fileURL } // Keep original (maybe temp) file URL when file moving fails
    return uniqueDestinationURL
}

/// Timestamps travel in encrypted metadata because ZIP timestamps have limited precision.
/// Walk real entries rather than resolving received paths, and never follow symbolic links.
enum TransferModificationDates {
    static func capture(at url: URL, rootName: String? = nil) throws -> [String: Date] {
        var dates: [String: Date] = [:]
        try visit(at: url, relativePath: rootName ?? url.lastPathComponent) { item, path in
            dates[path] = try item.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
        return dates
    }

    static func restore(_ dates: [String: Date], at url: URL, rootName: String) throws {
        guard !dates.isEmpty else { return } // Transfers from older clients have no timestamps.
        try visit(at: url, relativePath: rootName) { item, path in
            if let date = dates[path] {
                try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: item.path)
            }
        }
    }

    private static func visit(at url: URL, relativePath: String, action: (URL, String) throws -> Void) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else { return }
        if attributes[.type] as? FileAttributeType == .typeDirectory {
            let children = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            for child in children {
                try visit(at: child, relativePath: relativePath + "/" + child.lastPathComponent, action: action)
            }
        }
        // Children first, so directory timestamps are restored last.
        try action(url, relativePath)
    }
}
