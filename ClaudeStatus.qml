import QtQuick
import Quickshell
import Quickshell.Io

// Live Claude Code status, read off the files that omarchy-claude-status
// writes from Claude Code's hooks.
//
// Everything this fork adds to the stock agents widget lives in this file and
// in ClaudeSessions.qml. Panel.qml carries only a handful of lines wiring them
// in, so a new Omarchy release can be re-cloned and re-patched by ./resync
// instead of hand-merging a thousand lines. Keep it that way: anything added
// to Panel.qml is something resync has to re-apply forever.
Item {
  id: root
  visible: false

  // Painted colours come from the panel, so the theme stays in one place.
  property color foreground: "#ffffff"
  property color dim: "#888888"

  // The bar button whose opacity breathes while a session is live.
  property Item breathTarget: null

  readonly property string stateDir:
    Quickshell.env("HOME") + "/.local/state/omarchy/claude-status"

  property string status: "idle"
  property string detail: ""
  property var sessions: []

  // The writer caps every field it produces, but this side reads files it did
  // not write and must not depend on that: the panel builds a row per entry
  // and a Text per row, so an oversized file is a rendering cost, not just a
  // parsing one. Both limits sit above anything the hook can legitimately
  // produce (MAX_SESSIONS=100, MAX_LABEL_CHARS=64 in bin/omarchy-claude-status).
  readonly property int maxSessions: 100
  readonly property int maxFieldChars: 64

  // One field, trimmed of control characters and cut to length. Control
  // characters matter beyond tidiness: a newline in a label would make one
  // row draw as two and push the rest of the panel down.
  function safeField(value, limit) {
    var cap = limit === undefined ? maxFieldChars : limit
    var text = String(value === undefined || value === null ? "" : value)
    text = text.replace(/[\x00-\x1f\x7f]/g, "").trim()
    return text.length > cap ? text.substring(0, cap) : text
  }

  // ------------------------------------------------------------------ input

  function applyState(content) {
    var lines = String(content || "").split("\n")
    root.status = safeField(lines[0], 16) || "idle"
    // A full-length label plus the " +N more" suffix, so a long project name
    // does not push the count of the other live sessions off the end.
    root.detail = safeField(lines.length > 1 ? lines[1] : "", maxFieldChars + 16)
  }

  function applySessions(content) {
    var out = []
    var lines = String(content || "").split("\n")
    for (var i = 0; i < lines.length && out.length < maxSessions; i++) {
      // rank, state, label, mtime — a short line is a torn read, not a row.
      var parts = lines[i].split("\t")
      if (parts.length < 4) continue
      var state = safeField(parts[1])
      if (state === "") continue
      var updatedMs = Number(parts[3]) * 1000
      out.push({
        state: state,
        label: safeField(parts[2]),
        updatedMs: isFinite(updatedMs) ? updatedMs : 0
      })
    }
    root.sessions = out
  }

  FileView {
    path: root.stateDir + "/state"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyState(text())
    onLoadFailed: root.applyState("")
  }

  FileView {
    path: root.stateDir + "/sessions.tsv"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applySessions(text())
    onLoadFailed: root.sessions = []
  }

  // ----------------------------------------------------------------- colour

  // Reading the status colour out of a theme role does not survive contact
  // with real themes: BlackTurq resolves both accent and urgent to nearly the
  // same cyan, so "working" and "idle" would be the same icon. This borrows
  // the theme's own saturation and lightness — the parts tuned to contrast
  // with this bar, in a light theme as much as a dark one — and moves only
  // the hue, which is the part that has to differ. Blue and amber stay apart
  // under the common kinds of colour blindness.
  function statusHue(degrees) {
    return Qt.hsla(degrees / 360,
                   Math.max(0.55, foreground.hslSaturation),
                   Math.min(0.72, foreground.hslLightness),
                   1.0)
  }

  // Blue reads as calm and busy, amber as your turn, magenta as stuck partway
  // through and unable to go on without you. Shared by the bar icon and every
  // row in the Sessions list, so a colour means one thing in both places.
  function colorForStatus(state) {
    return state === "blocked" ? statusHue(310)
      : state === "waiting" ? statusHue(40)
      : state === "working" ? statusHue(210)
      : dim
  }

  readonly property color statusColor:
    status === "idle" ? foreground : colorForStatus(status)

  // ------------------------------------------------------------------ words

  // "Claude · waiting on you — api-server +2 more"
  readonly property string tooltipText: {
    var head = status === "blocked" ? "Claude · needs an answer"
      : status === "waiting" ? "Claude · waiting on you"
      : status === "working" ? "Claude · working"
      : ""
    if (head === "") return ""
    return detail === "" ? head : head + " — " + detail
  }

  // Kept here rather than borrowed from Panel.qml so the fork's additions do
  // not depend on a stock helper that upstream is free to rename.
  function formatAge(ms) {
    if (!(ms > 0)) return "now"
    var minutes = Math.floor(ms / 60000)
    var hours = Math.floor(minutes / 60)
    var days = Math.floor(hours / 24)
    if (days > 0) return days + "d " + (hours % 24) + "h"
    if (hours > 0) return hours + "h " + (minutes % 60) + "m"
    return Math.max(1, minutes) + "m"
  }

  // ----------------------------------------------------------------- motion

  // Plenty of themes put accent within a few percent of the bar's own text
  // colour, so colour alone cannot be trusted to carry "working". The breath
  // can: slow and shallow while Claude thinks, quick and deep when it wants
  // an answer, still when nothing is running.
  readonly property real breathFloor: status === "working" ? 0.55 : 0.28
  readonly property int breathMs: status === "working" ? 1500 : 620

  SequentialAnimation {
    id: breathe
    loops: Animation.Infinite
    NumberAnimation {
      target: root.breathTarget; property: "opacity"
      to: root.breathFloor; duration: root.breathMs
      easing.type: Easing.InOutQuad
    }
    NumberAnimation {
      target: root.breathTarget; property: "opacity"
      to: 1.0; duration: root.breathMs
      easing.type: Easing.InOutQuad
    }
  }

  // Restarted rather than left running, so a working -> waiting switch picks
  // up the faster rhythm immediately instead of at the next loop.
  function syncBreath() {
    if (!breathTarget) return
    breathe.stop()
    breathTarget.opacity = 1.0
    if (status !== "idle") breathe.start()
  }

  onStatusChanged: syncBreath()
  onBreathTargetChanged: syncBreath()
  Component.onCompleted: syncBreath()
}
