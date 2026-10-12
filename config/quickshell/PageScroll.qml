pragma Singleton
import Quickshell
import QtQuick

// Page Up / Page Down for the scrollable windows, so a long settings page can be read
// without the mouse. It lives in one place so all the windows page the same way.
//
// Only Page Up and Page Down. Home and End would be natural too, but these windows have
// text fields (the Wi-Fi password, the launcher's search), where End must mean the end of
// the line, not of the document.
Singleton {
    // Keep a sliver of the previous screenful visible, so you do not lose your place in a
    // list of similar-looking switches.
    readonly property real overlap: 0.12

    // A view only pages when there is something below the fold. Otherwise report false, so
    // the key is not accepted and can do whatever it would have done.
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

    // Returns true if the key was used. The caller should assign it to event.accepted so an
    // unused key still reaches whatever is behind it.
    function handle(event, view) {
        if (event.key === Qt.Key_PageDown) return scroll(view, 1)
        if (event.key === Qt.Key_PageUp) return scroll(view, -1)
        return false
    }
}
