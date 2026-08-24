import QtQuick
import qs.Commons
import qs.Ui

// The SESSIONS block of the agents panel: one row per live Claude Code
// session, loudest first. The bar icon can only ever show one session; this
// is where you find out what the others are doing.
//
// Hides itself whole — separator included — when nothing is running.
Column {
  id: root

  property var claude: null
  property color foreground: "#ffffff"
  property color dim: "#888888"
  property string fontFamily: Style.font.family
  // Passed in rather than read from a clock of its own, so the ages tick over
  // on the same beat as the panel's reset countdowns.
  property double nowMs: 0

  readonly property var rows: claude ? claude.sessions : []

  visible: rows.length > 0
  spacing: Style.space(12)

  PanelSeparator {
    width: parent.width
    foreground: root.foreground
  }

  Column {
    width: parent.width
    spacing: Style.space(10)

    PanelSectionHeader {
      width: parent.width
      text: "SESSIONS"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    Repeater {
      model: root.rows

      SessionRow {
        required property var modelData
        width: parent.width
        session: modelData
      }
    }
  }

  // One session: a dot in its status colour, what the session is called, and
  // how long it has held that status. The age is the useful part once a couple
  // are open — it separates a session that just stopped from one that has been
  // waiting since this morning.
  component SessionRow: Item {
    id: sessionRow
    property var session: null

    readonly property string sessionState: session ? String(session.state || "") : ""
    readonly property color tint:
      root.claude ? root.claude.colorForStatus(sessionState) : root.dim

    implicitHeight: Math.max(sessionName.implicitHeight, sessionMeta.implicitHeight)

    Rectangle {
      id: sessionDot
      width: Style.space(7)
      height: width
      radius: width / 2
      color: sessionRow.tint
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: sessionName
      // A session started somewhere without a usable directory name still
      // deserves a row: it is one of the things holding the icon lit.
      text: sessionRow.session && sessionRow.session.label !== ""
        ? sessionRow.session.label : "untitled"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
      anchors.left: sessionDot.right
      anchors.leftMargin: Style.spacing.sm
      anchors.right: sessionMeta.left
      anchors.rightMargin: Style.spacing.sm
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: sessionMeta
      text: {
        var age = sessionRow.session ? Number(sessionRow.session.updatedMs) : 0
        if (!(age > 0) || !root.claude) return sessionRow.sessionState
        return sessionRow.sessionState + " · " + root.claude.formatAge(root.nowMs - age)
      }
      color: sessionRow.tint
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
    }
  }
}
