import AppKit

struct FormatGroup {
    let id: String
    let title: String
    let symbol: String
    let formats: [String]
}

enum FormatCatalog {
    static let groups: [FormatGroup] = [
        .init(id: "audio", title: "Audio", symbol: "waveform", formats: ["mp3", "wav", "flac", "aac", "m4a", "ogg", "wma", "aiff", "alac", "opus", "ape", "wv"]),
        .init(id: "video", title: "Video", symbol: "film", formats: ["mp4", "mov", "webm", "mkv", "avi", "gif", "m4v", "3gp", "flv", "ts", "mts", "m2ts", "wmv", "ogv", "mpg", "mpeg", "mxf", "vob"]),
        .init(id: "image", title: "Images", symbol: "photo", formats: ["png", "jpg", "jpeg", "heic", "webp", "tiff", "bmp", "ico", "icns", "avif"]),
        .init(id: "document", title: "Documents", symbol: "doc.text", formats: ["docx", "odt", "rtf", "md", "html", "tex", "epub", "mobi", "azw3"]),
        .init(id: "geo", title: "Geospatial", symbol: "map", formats: ["geojson", "gpkg", "shp", "kml", "kmz", "gpx", "gml", "wkt"]),
        .init(id: "config", title: "Structured data", symbol: "curlybraces", formats: ["json", "yaml", "yml", "plist", "toml"])
    ]
    static let all = Set(groups.flatMap(\.formats))
    static func menu(target: AnyObject, action: Selector) -> NSMenu {
        let menu = NSMenu(title: "Convert Here to")
        for group in groups {
            let item = NSMenuItem(title: group.title, action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: group.symbol, accessibilityDescription: nil)
            let submenu = NSMenu(title: group.title)
            for format in group.formats {
                let child = NSMenuItem(title: format.uppercased(), action: action, keyEquivalent: "")
                child.target = target; child.representedObject = format
                submenu.addItem(child)
            }
            item.submenu = submenu; menu.addItem(item)
        }
        return menu
    }
}
