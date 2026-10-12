# Cellar UI references

For visual changes, first select and inspect real app references, describe which spacing, hierarchy and interaction patterns will be adopted, then validate the running macOS UI. Do not invent a new visual language from a text prompt alone.

## Current direction

- Linear, “A calmer interface for a product in motion” (March 12, 2026): https://linear.app/now/behind-the-latest-design-refresh — subdued sidebar, softer separators, compact predictable actions.
- Craft, “Structure that adapts to your thinking”: https://www.craft.do/organize — recognizable spaces and uncluttered navigation hierarchy.
- Cellar's selected light macOS icon supplies the blue/violet accent; the content surfaces remain white with low-saturation neutral surroundings. No teal or coral theme. Preserve official provider logo colors.

## Project images

New project dialog and existing project edit dialog accept PNG, JPEG, HEIC and ICNS. Edit via the project header ellipsis or the sidebar context menu. Show the image in the sidebar, project header and credential project bindings. Without an image, show the name's first character.

Normalize the selected local image to a PNG thumbnail up to 256 pixels (fit, retain aspect ratio), limit original input to 20 MB and normalized output to 512 KiB, discard source path/metadata. Store inside the encrypted vault; existing projects missing iconPNG decode with no image. Image-only changes retain existing approvals; project renames invalidate grants. Thumbnail removal is reversible before Save via Cancel.

## Verification 0.7.3

Tests cover legacy decoding, image normalization, corrupt/oversized image rejection and persistence/removal through encrypted vault lock/unlock. A separate fake-key demo verified native file selection, preview, save, all three UI placements, removal preview and cancellation. No production credentials were revealed or changed.

## Menu bar access (0.7.4)

Reference: 1Password for Mac, https://support.1password.com/getting-started-mac/ — always-available menu-bar entry for quick access to the main app. Uses Apple's native MenuBarExtra menu: https://developer.apple.com/documentation/swiftui/menubarextra.

Cellar uses a small monochrome template rendition of its ribbon wine opener. macOS renders the appropriate foreground on light/dark menu bars. Menu actions: open the main window, authenticate/unlock, lock, add or deposit a new key, show a pending approval, quit. Closing the main window leaves the app and menu item running; quitting exits both. Unlock still requires OS authentication; a pending request opens the existing approval UI, without accepting it. The menu never displays secret values or project names; when locked, it reports backup status as unavailable.
