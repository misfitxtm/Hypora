pragma Singleton
import Quickshell
import QtQuick

// Page Up/Down for the scrollable windows, in one place; Home and End are left out because text fields need End.
Singleton {
    // Keep a sliver of the previous screenful visible so you do not lose your place.
    readonly property real overlap: 0.12

    // Page only when there is something below the fold, else report false so the key does its normal job.
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

    // Returns true if the key was used; assign it to event.accepted so unused keys still pass through.
    function handle(event, view) {
        if (event.key === Qt.Key_PageDown) return scroll(view, 1)
        if (event.key === Qt.Key_PageUp) return scroll(view, -1)
        return false
    }
}
