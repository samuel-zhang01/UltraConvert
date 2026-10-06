# UltraConvert artwork

The shipped icon is original, code-native vector artwork: a single U built from opposing arrows, a restrained blue/violet gradient and a pale tile. It is designed to remain legible at Finder sizes. Editable SVG is `logo.svg`; `scripts/render_icon.swift` renders clean alpha, and `scripts/build_brand.py` creates PNG sizes and ICNS. These assets share the project's MIT licence.

Built-in image generation was used for initial design exploration with this brief: “A minimal macOS icon for UltraConvert, a geometric U made of two opposing arrows, blue to subtle violet, pale icy frosted rounded-square tile, no text or decoration, crisp at small sizes.” Generated explorations were not shipped: the final vector source gives reproducible geometry and transparent edges. No API key or paid external design service was used.

The current package uses a static ICNS icon for compatibility. It does not claim dynamic Icon Composer/Liquid Glass appearances. Design references: [Apple app icon guidance](https://developer.apple.com/design/human-interface-guidelines/app-icons) and [Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer).

Finder workflows use the same PNG in Automator's custom-image metadata and resources. The installer uses AppKit's [NSWorkspace.setIcon](https://developer.apple.com/documentation/appkit/nsworkspace/seticon(_:forfile:options:)) with the app ICNS for their Finder document icons, then preserves macOS resource forks during staging. Automator's generated custom-image structure and both branded rows in macOS 27's Finder Settings list were inspected locally on 2026-10-06.
