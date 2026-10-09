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
    static func advice(_ format: String) -> String {
        let detail: String
        switch format {
        case "mp3": detail = "Widely compatible audio. Smaller files with some quality loss."
        case "wav", "aiff": detail = "Uncompressed audio for editing. Usually larger files."
        case "flac", "alac", "ape", "wv": detail = "Lossless audio. Keeps the source's decoded audio quality; cannot restore detail already lost."
        case "aac", "m4a": detail = "Compact audio, useful with Apple devices. The output uses AAC compression."
        case "opus", "ogg": detail = "Compact compressed audio. Check the receiving app supports it."
        case "wma": detail = "Audio for Windows workflows. Check the receiving app's codec support."
        case "png": detail = "Lossless image with transparency support. Good for screenshots and graphics."
        case "jpg", "jpeg": detail = "Widely compatible photos. Some quality loss; transparency is not supported."
        case "webp", "avif", "heic": detail = "Compact modern images. Check support in the receiving app or website."
        case "tiff": detail = "Image format for editing and print workflows. Files may be large."
        case "bmp": detail = "Basic bitmap images for older workflows. Usually large files."
        case "ico": detail = "Windows icon file. Review the generated icon sizes."
        case "icns": detail = "macOS icon file with multiple image sizes."
        case "mp4", "m4v": detail = "Common video container for sharing. Conversion may change quality and file size."
        case "mov": detail = "QuickTime video container. Codec support varies between players."
        case "webm", "ogv": detail = "Video for compatible web players. Check the target browser or app."
        case "mkv": detail = "Flexible video container. Playback depends on the contained codecs."
        case "gif": detail = "Animation without audio. Limited colours; large clips may produce large files."
        case "avi", "3gp", "flv", "wmv", "mpg", "mpeg", "vob": detail = "Video for older devices or workflows. Check the recipient's required format."
        case "ts", "mts", "m2ts", "mxf": detail = "Video for camera, broadcast or transport workflows. Check codec and receiving-app requirements."
        case "docx", "odt", "rtf": detail = "Editable document. Review layout, fonts and formatting after conversion."
        case "md": detail = "Markdown text for writing and version control. Complex document layout can change."
        case "html": detail = "Web document. Images and other companion files may be saved together."
        case "tex": detail = "LaTeX source for typesetting. UltraConvert does not execute TeX code."
        case "epub": detail = "Reflowable ebook. Review images and layout in an ebook reader."
        case "mobi", "azw3": detail = "Ebook for compatible Kindle workflows. Only unencrypted inputs are supported."
        case "gpkg": detail = "GeoPackage: a single-file geospatial database. Review layers and coordinate reference systems."
        case "shp": detail = "Shapefile with companion files. Keep the complete output folder together."
        case "geojson", "kml", "kmz", "gpx", "gml", "wkt": detail = "Geospatial data. Coordinate systems and geometry support matter; review the result."
        case "json", "yaml", "yml", "plist", "toml": detail = "Structured data. Values must be representable in the target format; comments and formatting can change."
        default: return "Choose a compatible format for the app that will open your result."
        }
        return (format == "alac" ? "ALAC (.m4a)" : format.uppercased()) + " · " + detail
    }
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
