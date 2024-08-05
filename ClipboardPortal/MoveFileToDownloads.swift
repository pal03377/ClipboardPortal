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
