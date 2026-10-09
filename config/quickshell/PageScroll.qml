pragma Singleton
import Quickshell
import QtQuick

// Page Up / Page Down for the scrollable windows, so a long settings page can be read
// without reaching for the mouse.
//
// One place rather than a copy per window: the windows differ in layout but not in what
// paging should mean, and eleven near-identical key handlers is how they drift apart.
//
// Deliberately only Page Up and Page Down. Home and End are the obvious companions, but
// these windows contain text fields — the Wi-Fi password, the launcher's search — and a
// key that jumps to the end of a *document* when you meant the end of a *line* is worse
// than not having it.
Singleton {
    // Keep a sliver of the previous screenful visible, so the eye has something to land
    // on. A full-height jump loses your place in a list of switches that all look alike.
    readonly property real overlap: 0.12

    // A view only pages when there is something below the fold. Reporting false otherwise
    // leaves the key unaccepted, so it can still do whatever it would have done.
    function pageable(view) {
        return !!view && view.height > 0 && view.contentHeight > view.height
    }

    function scroll(view, pages) {
        if (!pageable(view)) return false
        const limit = view.contentHeight - view.height
        const step = view.height * (1 - overlap) * pages
        const next = Math.max(0, Math.min(limit, view.contentY + step))
        if (next === view.contentY) return false   // already at that end
        view.contentY = next
        return true
    }

    // Returns true when the key was used, which the caller should assign to
    // event.accepted so an unused key still reaches whatever is behind it.
    function handle(event, view) {
        if (event.key === Qt.Key_PageDown) return scroll(view, 1)
        if (event.key === Qt.Key_PageUp) return scroll(view, -1)
        return false
    }
}
