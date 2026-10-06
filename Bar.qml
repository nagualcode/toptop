import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import qs.Commons
import qs.Ui
import "BarModel.js" as BarModel

// nagualcode.toptop — the Omarchy bar as a top-centre notch.
//
// Derived from omarchy.bar, with three changes:
//
//   * The bar is a notch: one rounded-bottom-corner block centred at the top of
//     the screen, holding all three layout sections side by side with no gap
//     between them. Everything to either side of it is plain desktop.
//   * It reserves no screen space (ExclusionMode.Ignore), so windows run the
//     full height of the screen and the notch is drawn over them.
//   * It is dynamic: collapsed it shows only the clock and the battery, and it
//     grows outwards to reveal the left and right sections while hovered.
//
// Everything else — widget hosting, panels, tooltips, drag-to-reorder,
// omarchy-toggle-bar — is upstream behaviour, unchanged. Changes are marked
// with `nagualcode.toptop` so re-syncing with upstream stays tractable.

Item {
  id: root

  // The omarchy-shell host injects omarchyPath from OMARCHY_PATH.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  // Injected by the host shell so bar slots can resolve enabled widgets.
  property var barWidgetRegistry: fallbackBarWidgetRegistry
  // Read-only registry view for third-party full bars; the built-in bar does
  // not otherwise need it, but declaring it keeps clone construction atomic.
  property var pluginRegistry: null
  // Injected by the host shell every time shell.json is reloaded. Holds the
  // `bar:` subtree: position, centerAnchor, layout. The host owns file IO;
  // the bar just renders whatever it's handed. The bar font follows the
  // OS-level fontconfig monospace binding — it is not stored in shell.json.
  property var barConfig: ({})
  // Injected by the host shell. Used for shell-wide actions such as opening
  // settings and persisting inline widget state.
  property var shell: null
  // Manifest for the active bar option. Present for custom bars and useful for
  // diagnostics; the built-in bar does not otherwise need it.
  property var manifest: null
  QtObject {
    id: fallbackBarWidgetRegistry
    property var widgets: ({})
    property int revision: 0
    function metadataFor(id) { return null }
  }
  // Mirrors the on-disk `bar-off` flag so the user can hide the bar without
  // killing the entire shell. Hidden panels stay mapped but park off-screen
  // without an exclusion zone; updated by the FileView watcher further down.
  property bool barHidden: false
  property string home: Quickshell.env("HOME")
  property string stateHome: home + "/.local/state"
  property string omarchyConfigDir: home + "/.config/omarchy"
  property var fallbackBarConfig: ({
    position: "top",
    transparent: false,
    centerAnchor: "omarchy.clock",
    layout: { left: [], center: [], right: [] }
  })
  property var layoutConfig: fallbackBarConfig.layout
  // nagualcode.toptop: still read from `bar.centerAnchor` so that key keeps
  // working, but no longer used to pin or to split anything — upstream needed an
  // anchor to hang the centre section's two halves off, and a notch has one
  // undivided centre instead. See autoPinnedIds for what decides visibility now.
  property string centerAnchor: ""
  property bool requestedTransparent: false
  property bool useTransparentForeground: false
  property bool transparent: false

  // nagualcode.toptop: hover state. The collapsed notch is the only pointer
  // target, and revealing sections can slide a neighbour out from under a
  // stationary pointer — so, exactly as upstream does for the indicator peek,
  // collapsing waits for the pointer to actually leave the notch.
  property bool notchHovered: false
  // Mirrors the on-disk `toptop-stay-open` flag. When the flag is present the
  // notch never folds: the bar is pinned open at full width and hover only
  // ever leaves it alone. Updated by the same FileView watcher that feeds
  // `barHidden`, and nudged by `bin/omarchy-toggle-toptop-hover`.
  property bool hoverRevealEnabled: true
  // Folding-off means the notch must sit at full width no matter what the
  // pointer is doing. Run through a root function: `collapseTimer` is an id, not
  // a property, so calling `root.collapseTimer` from a nested scope reads
  // undefined and the guard below would abort before `reveal` is ever set.
  function forceOpen() {
    collapseTimer.stop()
    reveal = 1
  }
  onHoverRevealEnabledChanged: if (!root.hoverRevealEnabled) root.forceOpen()
  // A panel can ask the bar to stop peeking while it is open (upstream calls
  // this centerHoverRevealSuppressed). Kept, because omarchy.indicators and
  // several third-party panels set it on the bar they are mounted in.
  property bool centerHoverRevealSuppressed: false
  // 0 = collapsed to the pinned widgets, 1 = every section at full width.
  // Every reveal group is a fraction of this, so one animated property
  // drives the whole bar and the sections cannot drift out of step.
  property real reveal: 0
  property int revealDelay: 120
  property int revealDuration: 180
  // Radius of the notch's bottom corners, and the breathing room at its ends.
  property real cornerRadius: Style.cornerRadius
  property int endPadding: Style.space(8)

  // nagualcode.toptop: widget ids that survive the collapse, from the
  // `toptop.pinned` list in shell.json. Empty means "work it out", which is
  // autoPinnedIds below.
  property var pinnedIds: []

  property int barConfigSerial: 0
  property string position: "top"
  // Resolves through fontconfig at paint time (Style.font.family defaults
  // to "monospace"), so changing the system font (via `omarchy-font-set`)
  // updates the bar without a reload.
  property string fontFamily: Style.font.family
  // Bound to the central Color singleton so the bar tracks shell.toml's
  // [bar] section. Property names kept for the rest of this file's bindings.
  property color themeForeground: Color.bar.text
  property color themeContrastForeground: Color.background
  property color transparentForeground: Color.bar.text
  property color foreground: themeForeground
  property color barForeground: useTransparentForeground ? transparentForeground : themeForeground
  property bool foregroundAnimationEnabled: true
  property color background: Color.bar.background
  property color urgent: Color.bar.active

  Behavior on barForeground { enabled: root.foregroundAnimationEnabled; ColorAnimation { duration: 420; easing.type: Easing.InOutCubic } }
  Behavior on background { ColorAnimation { duration: 420; easing.type: Easing.InOutCubic } }
  Behavior on urgent { ColorAnimation { duration: 420; easing.type: Easing.InOutCubic } }
  property var tooltipTarget: null
  property var pendingTooltipTarget: null
  property string tooltipText: ""
  property string pendingTooltipText: ""
  property bool tooltipShown: false
  property int tooltipRequest: 0
  property var activePopout: null
  property var barDragSource: null
  property var barDragTarget: null
  property var barDragTargetGeometry: null
  property bool barDragAfter: false
  property var barDragWindow: null
  property var barDragScreen: null
  property url barDragImageUrl: ""
  property real barDragSceneX: 0
  property real barDragSceneY: 0
  property real barDragScreenX: 0
  property real barDragScreenY: 0
  property real barDragOffsetX: 0
  property real barDragOffsetY: 0
  // nagualcode.toptop: upstream also tracks a bar being dragged to another
  // screen edge (barMove*). A notch has no other edge, so that gesture and its
  // ghost preview are gone; dragging a widget to reorder it is untouched.
  property var clickTargets: []
  property var moduleSlots: []
  property var pluginBarApis: ({})
  property var pluginObjectOwners: []

  Component {
    id: pluginBarApiComponent
    PluginBarApi { }
  }

  function publicLayoutConfig() {
    return JSON.parse(JSON.stringify(root.layoutConfig || {}))
  }

  function bindPluginBarApi(api) {
    if (!api) return
    api.foreground = Qt.binding(function() { return root.foreground })
    api.barForeground = Qt.binding(function() { return root.barForeground })
    api.background = Qt.binding(function() { return root.background })
    api.urgent = Qt.binding(function() { return root.urgent })
    api.fontFamily = Qt.binding(function() { return root.fontFamily })
    api.position = Qt.binding(function() { return root.position })
    api.vertical = Qt.binding(function() { return root.vertical })
    api.barSize = Qt.binding(function() { return root.barSize })
    api.transparent = Qt.binding(function() { return root.transparent })
    api.foregroundAnimationEnabled = Qt.binding(function() { return root.foregroundAnimationEnabled })
    // nagualcode.toptop: upstream publishes "the center section is peeking" here.
    // For the notch the equivalent is the whole bar being open, so the same
    // signal drives it — omarchy.indicators reveals its inactive indicators on
    // the same hover that unfolds the left and right sections.
    api.centerSectionRevealHeld = Qt.binding(function() { return root.revealHeld })
    api._centerHoverRevealSuppressed = Qt.binding(function() { return root.centerHoverRevealSuppressed })
    root.syncPluginBarApiObjects(api)
  }

  function syncPluginBarApiObjects(api) {
    if (!api) return
    api.activePopout = root.pluginOwnsBarObject(api.pluginId, root.activePopout)
      ? root.activePopout : (root.activePopout ? api.foreignPopoutMarker : null)
    api.clickTargets = root.pluginClickTargets(api.pluginId)
    api.layoutConfig = root.publicLayoutConfig()
  }

  function pluginObjectRecord(target) {
    for (var i = 0; i < pluginObjectOwners.length; i++) {
      var record = pluginObjectOwners[i]
      if (record && record.target === target) return record
    }
    return null
  }

  function markPluginObject(pluginId, target, role) {
    var key = String(pluginId || "")
    if (!key || !target) return false
    var record = root.pluginObjectRecord(target)
    if (record && record.pluginId !== key) return false
    var next = []
    for (var i = 0; i < pluginObjectOwners.length; i++) {
      var existing = pluginObjectOwners[i]
      if (!existing || existing.target !== target) next.push(existing)
    }
    var updated = record || { target: target, pluginId: key, clickTarget: false, popout: false }
    updated[role] = true
    next.push(updated)
    pluginObjectOwners = next
    return true
  }

  function unmarkPluginObject(pluginId, target, role) {
    var key = String(pluginId || "")
    var next = []
    for (var i = 0; i < pluginObjectOwners.length; i++) {
      var record = pluginObjectOwners[i]
      if (!record || record.target !== target || record.pluginId !== key) {
        next.push(record)
        continue
      }
      record[role] = false
      if (record.clickTarget || record.popout) next.push(record)
    }
    pluginObjectOwners = next
  }

  function pluginOwnsBarObject(pluginId, target) {
    var record = target ? root.pluginObjectRecord(target) : null
    return !!record && record.pluginId === String(pluginId || "")
  }

  function pluginClickTargets(pluginId) {
    var out = []
    for (var i = 0; i < root.clickTargets.length; i++) {
      var target = root.clickTargets[i]
      if (root.pluginOwnsBarObject(pluginId, target)) out.push(target)
    }
    return out
  }

  function syncAllPluginBarApiObjects() {
    for (var id in pluginBarApis) root.syncPluginBarApiObjects(pluginBarApis[id])
  }

  function registerPluginClickTarget(pluginId, target) {
    if (!root.markPluginObject(pluginId, target, "clickTarget")) return
    root.registerClickTarget(target)
  }

  function unregisterPluginClickTarget(pluginId, target) {
    if (!root.pluginOwnsBarObject(pluginId, target)) return
    root.unregisterClickTarget(target)
    root.unmarkPluginObject(pluginId, target, "clickTarget")
  }

  function requestPluginPopout(pluginId, owner) {
    if (!root.markPluginObject(pluginId, owner, "popout")) return
    root.requestPopout(owner)
  }

  function releasePluginPopout(pluginId, owner) {
    if (!root.pluginOwnsBarObject(pluginId, owner)) return
    root.releasePopout(owner)
    root.unmarkPluginObject(pluginId, owner, "popout")
  }

  function pluginBarApiFor(pluginId, moduleName, registered) {
    var key = String(pluginId || "")
    if (!key) return null

    var pluginShell = null
    if (registered && root.shell && typeof root.shell.pluginShellForId === "function") {
      // Only the trusted built-in bar receives ShellRoot and can request a
      // service-capable facade for the widget it is instantiating.
      pluginShell = root.shell.pluginShellForId(moduleName)
    } else if (root.shell && typeof root.shell.pluginShellForBarEntry === "function") {
      // Replacement bars receive a service-less entry facade. Giving an
      // untrusted bar a generic facade factory would let it retrieve another
      // third-party plugin's live service object.
      pluginShell = root.shell.pluginShellForBarEntry(key, moduleName)
    }

    if (pluginBarApis[key]) {
      pluginBarApis[key].shell = pluginShell
      return pluginBarApis[key]
    }

    var api = pluginBarApiComponent.createObject(null, {
      pluginId: key,
      moduleName: String(moduleName || ""),
      shell: pluginShell,
      _showTooltip: function(target, text) { root.showTooltip(target, text) },
      _hideTooltip: function(target) { root.hideTooltip(target) },
      _registerClickTarget: function(target) { root.registerPluginClickTarget(key, target) },
      _unregisterClickTarget: function(target) { root.unregisterPluginClickTarget(key, target) },
      _requestPopout: function(owner) { root.requestPluginPopout(key, owner) },
      _releasePopout: function(owner) { root.releasePluginPopout(key, owner) },
      _switchPanelFrom: function(owner, direction) { return root.switchPanelFrom(owner, direction) },
      _targetBelongsToWindow: function(target, window) { return root.targetBelongsToWindow(target, window) },
      _moduleWidgets: function(requestedId) {
        return String(requestedId || "") === String(moduleName || "")
          ? root.moduleWidgets(moduleName) : []
      },
      _run: function(command) { root.run(command) },
      _setCenterHoverRevealSuppressed: function(value) {
        root.centerHoverRevealSuppressed = !!value
      }
    })
    if (!api) return null
    root.bindPluginBarApi(api)

    var next = ({})
    for (var id in pluginBarApis) next[id] = pluginBarApis[id]
    next[key] = api
    pluginBarApis = next
    return api
  }

  function pluginBarApiUsed(pluginId) {
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (slot && slot.pluginApiId === pluginId) return true
    }
    return false
  }

  function releasePluginObjects(pluginId) {
    var owned = pluginObjectOwners.slice()
    for (var i = 0; i < owned.length; i++) {
      var record = owned[i]
      if (!record || record.pluginId !== pluginId) continue
      if (record.clickTarget) root.unregisterClickTarget(record.target)
      if (record.popout && root.activePopout === record.target) root.releasePopout(record.target)
    }
    pluginObjectOwners = pluginObjectOwners.filter(function(record) {
      return record && record.pluginId !== pluginId
    })
  }

  function prunePluginBarApis() {
    var next = ({})
    for (var id in pluginBarApis) {
      var api = pluginBarApis[id]
      if (root.pluginBarApiUsed(id)) {
        next[id] = api
        continue
      }
      root.releasePluginObjects(id)
      if (api && typeof api.destroy === "function") api.destroy()
    }
    pluginBarApis = next
  }

  onActivePopoutChanged: syncAllPluginBarApiObjects()
  onClickTargetsChanged: syncAllPluginBarApiObjects()
  onLayoutConfigChanged: syncAllPluginBarApiObjects()
  onModuleSlotsChanged: Qt.callLater(prunePluginBarApis)

  Component.onDestruction: {
    for (var id in pluginBarApis) {
      root.releasePluginObjects(id)
      if (pluginBarApis[id] && typeof pluginBarApis[id].destroy === "function")
        pluginBarApis[id].destroy()
    }
    pluginBarApis = ({})
  }

  function registerClickTarget(target) {
    if (!target || clickTargets.indexOf(target) !== -1) return
    var next = clickTargets.slice()
    next.push(target)
    clickTargets = next
  }

  function unregisterClickTarget(target) {
    var next = clickTargets.filter(function(item) { return item !== target })
    clickTargets = next
  }

  function registerModuleSlot(slot) {
    if (!slot || moduleSlots.indexOf(slot) !== -1) return
    var next = moduleSlots.slice()
    next.push(slot)
    moduleSlots = next
  }

  function unregisterModuleSlot(slot) {
    var next = moduleSlots.filter(function(item) { return item !== slot })
    moduleSlots = next
  }

  function debugBarGeometry() {
    var out = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem) continue
      var point = { x: slot.x, y: slot.y }
      try {
        point = slot.mapToItem(null, 0, 0)
      } catch (e) {
      }
      out.push({
        id: slot.moduleName,
        section: slot.region,
        x: Math.round(point.x),
        y: Math.round(point.y),
        width: Math.round(slot.width),
        height: Math.round(slot.height),
        visible: slot.visible === true && slot.width > 0 && slot.height > 0,
        itemVisible: slot.activeItem.visible === true,
        itemWidth: Math.round(slot.activeItem.implicitWidth || 0),
        itemHeight: Math.round(slot.activeItem.implicitHeight || 0)
      })
    }
    return out
  }

  function targetWindow(target) {
    return target && target.QsWindow ? target.QsWindow.window : null
  }

  function targetBelongsToWindow(target, window) {
    return !!target && !!window && targetWindow(target) === window
  }

  function slotWindow(slot) {
    if (!slot) return null
    return targetWindow(slot.activeItem) || targetWindow(slot)
  }

  function sameWindow(left, right) {
    if (!left || !right) return false
    if (left === right) return true
    return !!left.screen && !!right.screen && !!left.screen.name && !!right.screen.name && left.screen.name === right.screen.name
  }

  function targetTooltipHovered(target) {
    return !!target && target.visible !== false && target.opacity !== 0 && target.tooltipHovered === true
  }

  function clearTooltip() {
    tooltipTimer.stop()
    pendingTooltipTarget = null
    pendingTooltipText = ""
    tooltipTarget = null
    tooltipText = ""
    tooltipShown = false
  }

  function clearBarDrag() {
    barDragSource = null
    barDragWindow = null
    barDragScreen = null
    barDragImageUrl = ""
    barDragTarget = null
    barDragTargetGeometry = null
    barDragAfter = false
    barDragSceneX = 0
    barDragSceneY = 0
    barDragScreenX = 0
    barDragScreenY = 0
    barDragOffsetX = 0
    barDragOffsetY = 0
  }

  function windowScreenPoint(scenePoint, window) {
    var x = scenePoint ? scenePoint.x : 0
    var y = scenePoint ? scenePoint.y : 0
    if (!window || !window.screen) return { x: x, y: y }

    if (root.position === "bottom")
      y += Math.max(0, window.screen.height - window.height)
    else if (root.position === "right")
      x += Math.max(0, window.screen.width - window.width)

    return { x: x, y: y }
  }

  function barDragScreenPoint(scenePoint) {
    return windowScreenPoint(scenePoint, barDragWindow)
  }

  function dropMarkerRect(slot, after) {
    if (!slot) return null

    try {
      var slotPoint = slot.mapToItem(null, 0, 0)
      var screenPoint = barDragScreenPoint(slotPoint)
      var thickness = Style.spacing.xs
      if (vertical) {
        return {
          x: screenPoint.x,
          y: screenPoint.y + (after ? slot.height : 0) - thickness / 2,
          width: slot.width,
          height: thickness
        }
      }

      return {
        x: screenPoint.x + (after ? slot.width : 0) - thickness / 2,
        y: screenPoint.y,
        width: thickness,
        height: slot.height
      }
    } catch (e) {
      return null
    }
  }

  // nagualcode.toptop: upstream's nearestScreenEdge/beginBarMove/updateBarMove/
  // clearBarMove/finishBarMove/setBarPosition are removed — they drove the
  // drag-the-bar-to-another-edge gesture, which a top-centre notch has no
  // meaning for. `position` is pinned to "top" in applyBarConfig instead.

  function captureBarDragGhost(slot) {
    var item = slot && slot.activeItem ? slot.activeItem : null
    barDragImageUrl = ""
    if (!item || typeof item.grabToImage !== "function") return

    var grabWidth = Math.max(1, Math.ceil(item.width || item.implicitWidth || slot.width || 1))
    var grabHeight = Math.max(1, Math.ceil(item.height || item.implicitHeight || slot.height || 1))
    item.grabToImage(function(result) {
      if (root.barDragSource !== slot || !result || !result.url) return
      root.barDragImageUrl = result.url
    }, Qt.size(grabWidth, grabHeight))
  }

  function requestPopout(owner) {
    if (activePopout === owner) return
    if (activePopout) {
      if ("closeForPopoutSwitch" in activePopout) activePopout.closeForPopoutSwitch()
      else if ("close" in activePopout) activePopout.close()
    }
    activePopout = owner
  }

  function releasePopout(owner) {
    if (activePopout === owner) activePopout = null
  }

  readonly property bool vertical: position === "left" || position === "right"
  readonly property int barSize: vertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal

  function normalizePosition(value) {
    return BarModel.normalizePosition(value)
  }

  // Apply tray-pinning on top of the shared layout normalization so the
  // bar host and scriptable config helpers can't drift on entry shape.
  function normalizeLayout(layout) {
    var normalized = Util.normalizeLayout(Util.isPlainObject(layout) ? layout : fallbackBarConfig.layout)
    return {
      left:   pinTrayToInner(normalized.left,   "left"),
      center: pinTrayToInner(normalized.center, "center"),
      right:  pinTrayToInner(normalized.right,  "right")
    }
  }

  // The tray drawer reveals inward (away from the bar edge). Place it at the
  // section's inner edge: start of the right section, end of the left/center
  // sections. The drawer's reserved space then sits next to the bar center,
  // not stranded mid-section.
  function pinTrayToInner(entries, section) {
    return BarModel.pinTrayToInner(entries, section)
  }

  function applyBarConfig() {
    var config = Util.isPlainObject(barConfig) ? barConfig : fallbackBarConfig

    // nagualcode.toptop: the notch is a top-centre shape, so `position` from
    // shell.json is read but not obeyed. Without this, a config left at
    // "bottom" by some other bar would leave the notch pinned to the wrong
    // edge the first time toptop loaded. Everything downstream still reads
    // `position`/`vertical`, so they keep working — they just see "top".
    position = "top"
    setRequestedTransparency(config.transparent === true)
    centerAnchor = Util.canonicalWidgetId(config.centerAnchor || "")
    applyTopTopConfig(config.toptop)

    // layoutEntries feeds plain JS arrays to the module Repeaters, and QML
    // cannot diff those: reassigning layoutConfig rebuilds every widget on
    // every monitor. When a shell.json write only changed inline widget
    // settings, patch the live layout and running widgets in place instead.
    var next = normalizeLayout(config.layout)
    var delta = BarModel.inlineSettingsDelta(layoutConfig, next)
    if (delta) {
      applySettingsDelta(delta)
      return
    }
    layoutConfig = next
    barConfigSerial++
  }

  // nagualcode.toptop: the `toptop:` subtree of bar.json. Every key is
  // optional; an absent or malformed subtree falls back to the defaults above.
  //
  //   pinned         array of widget ids that stay visible while collapsed.
  //                  Empty (the default) means "work it out" — see
  //                  autoPinnedIds. Listing ids here *adds* to the automatic
  //                  set rather than replacing it, so adding one extra always-on
  //                  icon does not cost you the clock.
  //   radius         bottom-corner radius in px. Defaults to the theme's.
  //   padding        space between the notch's ends and its outermost icons.
  //   revealDuration unfold/collapse animation, ms.
  //   revealDelay    how long after the pointer leaves before collapsing, ms.
  function applyTopTopConfig(settings) {
    var options = Util.isPlainObject(settings) ? settings : ({})

    var pinned = []
    if (Array.isArray(options.pinned)) {
      for (var i = 0; i < options.pinned.length; i++) {
        pinned.push(Util.canonicalWidgetId(String(options.pinned[i])))
      }
    }
    pinnedIds = pinned

    if (options.radius !== undefined && options.radius !== null) {
      cornerRadius = Math.max(0, Number(options.radius) || 0)
    }
    if (options.padding !== undefined && options.padding !== null) {
      endPadding = Math.max(0, Number(options.padding) || 0)
    }
    if (options.revealDuration !== undefined && options.revealDuration !== null) {
      revealDuration = Math.max(0, Number(options.revealDuration) || 0)
    }
    if (options.revealDelay !== undefined && options.revealDelay !== null) {
      revealDelay = Math.max(0, Number(options.revealDelay) || 0)
    }
  }

  // nagualcode.toptop: what the collapsed notch keeps.
  //
  // One automatic rule, and it is the layout itself: whatever is in the centre
  // section. Belonging to the centre *is* the rule, so the notch is reshaped by
  // dragging icons rather than by editing a list — drag an icon into the centre
  // and it stays visible when the notch folds, drag it back out and it starts
  // hiding again.
  //
  // Nothing is pinned implicitly. There is deliberately no rule for the clock
  // and none for batteries: move the clock out of the centre, or leave the
  // battery in a side section, and the folded notch stops showing it. The
  // `pinned` list in shell.json is how you ask for a specific icon instead of
  // moving it.
  readonly property var autoPinnedIds: {
    var ids = []
    var center = layoutConfig ? layoutConfig.center : null
    if (!Array.isArray(center)) return ids
    for (var i = 0; i < center.length; i++) {
      var id = Util.canonicalWidgetId(entryId(center[i]))
      if (id && ids.indexOf(id) < 0) ids.push(id)
    }
    return ids
  }

  function isPinnedName(name) {
    var id = Util.canonicalWidgetId(name)
    if (pinnedIds.indexOf(id) !== -1) return true
    return autoPinnedIds.indexOf(id) !== -1
  }

  // nagualcode.toptop: the layout split into the nine runs the notch is built
  // from — per section, the entries outside the always-visible ones (outer),
  // the always-visible ones themselves (pinned), and the entries between them
  // and the centre (inner).
  //
  // Order is preserved, so a section's icons stay in the order the layout put
  // them; only the collapsed/expanded question moves. Splitting into three
  // runs rather than two is what lets the pinned icons hold still while the
  // icons on both sides of them unroll outwards — with a single split, an
  // icon sitting between two pinned ones would be clipped away mid-animation
  // and pop back at the end.
  readonly property var notchGroups: buildNotchGroups()

  // nagualcode.toptop: how many entries the folded notch is showing. Zero only
  // when the centre section is empty, which is the one state with nothing worth
  // drawing — the surface keeps its width so it stays hoverable, but the shape
  // behind it is hidden rather than left as an empty pill floating at the top of
  // the screen.
  readonly property int pinnedEntryCount:
    notchGroups.left.pinned.length + notchGroups.center.pinned.length + notchGroups.right.pinned.length

  function buildNotchGroups() {
    var regions = ["left", "center", "right"]
    var out = {}

    for (var r = 0; r < regions.length; r++) {
      var region = regions[r]
      var parts = { outer: [], pinned: [], inner: [] }
      var seenPinned = false
      var entries = layoutEntries(region)

      for (var i = 0; i < entries.length; i++) {
        if (isPinnedName(entryId(entries[i]))) {
          parts.pinned.push(entries[i])
          seenPinned = true
        } else if (seenPinned) {
          parts.inner.push(entries[i])
        } else {
          parts.outer.push(entries[i])
        }
      }

      out[region] = parts
    }

    // An empty centre used to mean "fall back to the whole centre", which was
    // worth having when the pinned set was a guess about ids. Now the centre is
    // the rule, so an un-pinned bar can only mean the centre is empty and there
    // is genuinely nothing to show. Nothing to fall back to: the notch stays
    // empty, and an empty notch keeps its hover target so the bar can still be
    // summoned and an icon dragged back into the centre.

    return out
  }

  function applySettingsDelta(delta) {
    for (var i = 0; i < delta.length; i++) {
      var change = delta[i]
      layoutConfig[change.region][change.index] = change.entry
      var settings = entrySettings(change.entry)
      for (var s = 0; s < moduleSlots.length; s++) {
        var slot = moduleSlots[s]
        if (!slot || slot.region !== change.region || slot.moduleName !== entryId(change.entry)) continue
        var item = slot.activeItem
        if (item && "settings" in item) item.settings = settings
      }
    }
  }

  onBarConfigChanged: applyBarConfig()

  function layoutEntries(region) {
    var serial = barConfigSerial
    var entries = layoutConfig ? layoutConfig[region] : null
    return Array.isArray(entries) ? entries : []
  }

  // Tab order for the panels in one bar region. Scoped to a single bar surface
  // so tabbing walks the bar the open panel belongs to instead of hopping the
  // panel to another monitor's copy of the same widget.
  function panelNavigationSlots(region, window) {
    var entries = layoutEntries(region)
    var slots = []
    for (var i = 0; i < entries.length; i++) {
      var id = entryId(entries[i])
      for (var j = 0; j < moduleSlots.length; j++) {
        var slot = moduleSlots[j]
        if (!slot || slot.region !== region || slot.moduleName !== id) continue
        if (window && !sameWindow(slotWindow(slot), window)) continue
        var item = slot.activeItem
        if (!item || item.visible !== true || slot.visible !== true || slot.width <= 0 || slot.height <= 0) continue
        if (typeof item.open !== "function" || typeof item.close !== "function" || item.opened === undefined) continue
        slots.push(slot)
        break
      }
    }
    return slots
  }

  // The Nth panel in a bar region, counted the way the bar reads: layout order,
  // and only the panels actually on screen. A widget with no panel (the tray)
  // and one that is hiding itself are passed over, so the number lands on the
  // Nth panel icon the user can see rather than the Nth layout entry.
  // One-based, because it exists for hotkeys; anything else lands on no slot.
  //
  // Counting any bar surface is enough: every monitor lays its bar out from the
  // one layout, and summoning the id routes through pickPanelSlot, which opens
  // the focused monitor's copy whichever surface was counted.
  function panelWidgetIdAt(region, index) {
    var slots = panelNavigationSlots(String(region || ""), null)
    var slot = slots[Math.round(Number(index)) - 1]
    return slot ? String(slot.moduleName || "") : ""
  }

  function switchPanelFrom(owner, direction) {
    if (!owner) return false

    var currentSlot = null
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (slot && slot.activeItem === owner) {
        currentSlot = slot
        break
      }
    }
    if (!currentSlot) return false

    var slots = panelNavigationSlots(currentSlot.region, slotWindow(currentSlot))
    if (slots.length < 2) return false

    var currentIndex = -1
    for (var j = 0; j < slots.length; j++) {
      if (slots[j] === currentSlot) {
        currentIndex = j
        break
      }
    }
    if (currentIndex < 0) return false

    var step = direction < 0 ? -1 : 1
    var nextSlot = slots[(currentIndex + step + slots.length) % slots.length]
    if (!nextSlot || !nextSlot.activeItem || nextSlot.activeItem === owner) return false

    nextSlot.activeItem.open()
    return true
  }

  // Every live instance of a widget id. A bar surface is built per monitor, so
  // a widget that appears once in the layout is still live once per screen.
  function moduleWidgets(pluginId) {
    var id = String(pluginId || "")
    var items = []
    if (!id) return items
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem || slot.moduleName !== id) continue
      items.push(slot.activeItem)
    }
    return items
  }

  function slotScreenName(slot) {
    var window = slotWindow(slot)
    return window && window.screen ? String(window.screen.name || "") : ""
  }

  // The output Hyprland has focused, which is where a keyboard-summoned panel
  // belongs. Empty until Hyprland reports one, which leaves panel routing on
  // its per-monitor fallback rather than guessing at an output.
  function focusedScreenName() {
    var monitor = Hyprland.focusedMonitor
    return monitor ? String(monitor.name || "") : ""
  }

  // Resolve the live bar-widget instance for a plugin id (e.g. "omarchy.bluetooth").
  // Only widgets that expose popup open/close methods count; plain indicators
  // (clock, workspaces, tray) return null. Used by shell.summon/toggle so
  // panel hotkeys route through the bar instead of a per-target IPC handler
  // that only reaches whichever per-monitor instance claimed the target.
  function findPanelWidget(pluginId) {
    var id = String(pluginId || "")
    if (!id) return null
    var candidates = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem) continue
      if (slot.moduleName !== id) continue
      var item = slot.activeItem
      if (typeof item.open !== "function" || typeof item.close !== "function" || item.opened === undefined) continue
      candidates.push({ slot: slot, screenName: slotScreenName(slot), opened: item.opened === true })
    }
    // One copy per monitor, plus a zero-size placeholder for anchored center
    // modules. See BarModel.pickPanelSlot for which one a hotkey acts on.
    var chosen = BarModel.pickPanelSlot(candidates, focusedScreenName())
    return chosen ? chosen.activeItem : null
  }

  function summonBarWidget(pluginId) {
    var item = findPanelWidget(pluginId)
    if (!item || typeof item.open !== "function") return false
    item.open()
    return true
  }

  function hideBarWidget(pluginId) {
    var item = findPanelWidget(pluginId)
    if (!item || typeof item.close !== "function") return false
    item.close()
    return true
  }

  function isBarWidgetOpen(pluginId) {
    var item = findPanelWidget(pluginId)
    return !!item && item.opened === true
  }

  function entrySettings(entry) {
    return BarModel.entrySettings(entry)
  }

  function entryId(entry) {
    return BarModel.entryId(entry)
  }

  function moduleString(entry, key, fallback) {
    return BarModel.moduleString(entry, key, fallback)
  }

  // nagualcode.toptop: upstream's entryIndex/entriesBefore/entriesAfter are
  // gone. They existed to split the centre section around `centerAnchor`, which
  // pinned one widget to the exact middle of the screen — a job the notch does
  // by centring the whole bar, so there is nothing left to split around.

  function canonicalWidgetId(name) {
    return Util.canonicalWidgetId(name)
  }

  function expandPath(path) {
    return BarModel.expandPath(path, home)
  }

  function customModuleSafeName(name) {
    return BarModel.customModuleSafeName(name)
  }

  function customModuleType(entry) {
    return BarModel.customModuleType(entry)
  }

  function customModuleSource(entry) {
    var source = BarModel.customModulePath(entry, home, omarchyConfigDir)
    return source ? Util.fileUrl(source) : ""
  }

  Component.onCompleted: applyBarConfig()

  // nagualcode.toptop: unfolding the bar widens it, which can slide a
  // neighbouring section out from under a stationary pointer. Collapsing on
  // that un-hover would shrink it back out and re-open the notch, so hold the
  // reveal until the pointer has genuinely left — the same reason upstream
  // delays collapsing the indicator peek.
  function setNotchHovered(hovered) {
    notchHovered = hovered
    // When the stay-open flag is set the notch folds for no one: keep the bar
    // fully open and let hover lead nowhere.
    if (!root.hoverRevealEnabled) return
    if (hovered) {
      collapseTimer.stop()
      reveal = 1
    } else {
      collapseTimer.restart()
    }
  }

  // Whether the bar is currently unfolded. omarchy.indicators reads this as
  // `centerSectionRevealHeld` through the plugin API.
  readonly property bool revealHeld: reveal > 0

  // Keep the bar open while a panel it hosts is open, so a panel's own hover
  // suppression is never fighting the bar collapsing underneath it.
  function setCenterHoverRevealSuppressed(value) {
    centerHoverRevealSuppressed = !!value
    if (centerHoverRevealSuppressed) reveal = 1
    else if (!root.hoverRevealEnabled) reveal = 1
    else if (!notchHovered) collapseTimer.restart()
  }

  Behavior on reveal {
    NumberAnimation {
      duration: root.revealDuration
      easing.type: Easing.OutCubic
    }
  }

  Timer {
    id: collapseTimer
    interval: root.revealDelay
    // Collapse only. Unfolding is the notch's own gesture, done in
    // setNotchHovered, so a timer left pending by a pointer that dipped off the
    // bar and came back cannot unfold a notch it never pointed at.
    onTriggered: if (root.hoverRevealEnabled && !root.notchHovered) root.reveal = 0
  }

  function run(command) {
    if (!command) return

    Util.execDetached(command)
  }

  // nagualcode.toptop: where this plugin is installed, worked out from this
  // file's own location rather than an assumed $OMARCHY_PATH, so the widget
  // menu keeps working from a clone, a dev link, or a moved plugin directory.
  readonly property string pluginDir: {
    var dir = String(Qt.resolvedUrl("./"))
    return dir.indexOf("file://") === 0 ? dir.slice(7) : dir
  }

  // Single-quote for the login shell `run` hands the command to. The only thing
  // quoted is a path we chose ourselves, but a plugin directory is a place a
  // space can still turn up in.
  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  // Right-clicking the notch opens the installed-widgets menu. Run through
  // `bash` rather than executed directly so a lost executable bit (a copy, a
  // zip, a git checkout on a filesystem that dropped the mode) cannot leave the
  // button doing nothing at all.
  function manageWidgets() {
    run("bash " + shellQuote(pluginDir + "bin/omarchy-toptop-widgets"))
  }

  function toggleTransparency() {
    var nextTransparent = !(root.requestedTransparent === true)
    if (root.shell && typeof root.shell.mutateShellConfig === "function") {
      root.shell.mutateShellConfig(function(config) {
        if (!Util.isPlainObject(config.bar)) config.bar = {}
        config.bar.transparent = nextTransparent
      })
    } else {
      root.setRequestedTransparency(nextTransparent)
    }
  }

  function rawLayoutSection(config, region) {
    if (!Util.isPlainObject(config.bar)) config.bar = {}
    if (!Util.isPlainObject(config.bar.layout)) config.bar.layout = {}
    if (!Array.isArray(config.bar.layout[region])) config.bar.layout[region] = []

    return config.bar.layout[region]
  }

  function rawEntryIndex(entries, name) {
    for (var i = 0; i < entries.length; i++) {
      if (root.entryId(entries[i]) === name) return i
    }

    return -1
  }

  function moveModuleInConfig(config, fromRegion, fromName, toRegion, beforeName) {
    var fromEntries = rawLayoutSection(config, fromRegion)
    var toEntries = rawLayoutSection(config, toRegion)
    var fromIndex = rawEntryIndex(fromEntries, fromName)
    if (fromIndex < 0) return false

    var toIndex = beforeName ? rawEntryIndex(toEntries, beforeName) : toEntries.length
    if (toIndex < 0) toIndex = toEntries.length

    if (fromRegion === toRegion && fromIndex === toIndex) return false

    var movedEntry = fromEntries[fromIndex]
    fromEntries.splice(fromIndex, 1)

    if (fromRegion === toRegion && fromIndex < toIndex) toIndex -= 1
    if (toIndex < 0) toIndex = 0
    if (toIndex > toEntries.length) toIndex = toEntries.length
    if (fromRegion === toRegion && fromIndex === toIndex) {
      fromEntries.splice(fromIndex, 0, movedEntry)
      return false
    }

    toEntries.splice(toIndex, 0, movedEntry)
    return true
  }

  function dropBarModule(source, toRegion, beforeName) {
    if (!source || !source.region || !source.moduleName || !toRegion) return false
    if (source.region === toRegion && source.moduleName === beforeName) return false
    if (!root.shell || typeof root.shell.mutateShellConfig !== "function") return false

    var changed = false
    root.shell.mutateShellConfig(function(config) {
      changed = moveModuleInConfig(config, source.region, source.moduleName, toRegion, beforeName)
    })
    return changed
  }

  function moduleDropAtScene(scenePoint, sourceSlot) {
    var sourceWindow = root.slotWindow(sourceSlot) || root.barDragWindow
    if (sourceWindow && sourceWindow.contentItem) {
      var barPoint = sourceWindow.contentItem.mapFromItem(null, scenePoint.x, scenePoint.y)
      if (barPoint.x < 0 || barPoint.x > sourceWindow.contentItem.width ||
          barPoint.y < 0 || barPoint.y > sourceWindow.contentItem.height)
        return null
    }

    var candidates = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || slot === sourceSlot || !slot.visible || slot.width <= 0 || slot.height <= 0) continue
      if (sourceWindow && !root.sameWindow(root.slotWindow(slot), sourceWindow)) continue

      var slotPoint = { x: slot.x, y: slot.y }
      try {
        slotPoint = slot.mapToItem(null, 0, 0)
      } catch (e) {
      }

      candidates.push({
        slot: slot,
        x: slotPoint.x,
        y: slotPoint.y,
        width: slot.width,
        height: slot.height
      })
    }

    return BarModel.nearestDropTarget(candidates, scenePoint, root.vertical)
  }

  function visibleModuleSlot(region, name, sourceSlot) {
    var sourceWindow = root.slotWindow(sourceSlot) || root.barDragWindow
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || slot === sourceSlot || slot.region !== region || slot.moduleName !== name ||
          !slot.visible || slot.width <= 0 || slot.height <= 0) continue
      if (sourceWindow && !root.sameWindow(root.slotWindow(slot), sourceWindow)) continue
      return slot
    }

    return null
  }

  function nextVisibleModuleName(region, afterName, sourceSlot) {
    var entries = layoutEntries(region)
    var found = false
    for (var i = 0; i < entries.length; i++) {
      var name = entryId(entries[i])
      if (!found) {
        found = name === afterName
        continue
      }

      if (visibleModuleSlot(region, name, sourceSlot)) return name
    }

    return ""
  }

  function dropBarModuleAtTarget(sourceSlot, targetSlot, afterTarget) {
    if (!sourceSlot || !targetSlot) return false

    var beforeName = afterTarget ? nextVisibleModuleName(targetSlot.region, targetSlot.moduleName, sourceSlot) : targetSlot.moduleName
    return dropBarModule(sourceSlot, targetSlot.region, beforeName)
  }

  function moduleTargetClickable(target) {
    return target
      && target.visible !== false
      && target.opacity !== 0
      && target.interactive !== false
      && target.pressable !== false
      && target.concealed !== true
      && typeof target.triggerPress === "function"
  }

  function moduleClickTargetAt(slot, localX, localY) {
    for (var i = clickTargets.length - 1; i >= 0; i--) {
      var target = clickTargets[i]
      if (!moduleTargetClickable(target)) continue

      var targetPoint = { x: localX, y: localY }
      try {
        targetPoint = slot.mapToItem(target, localX, localY)
      } catch (e) {
        continue
      }

      if (targetPoint.x >= 0 && targetPoint.x <= target.width &&
          targetPoint.y >= 0 && targetPoint.y <= target.height) {
        return target
      }
    }

    if (moduleTargetClickable(slot.activeItem)) return slot.activeItem
    return null
  }

  function pressModuleClickTarget(slot, button, localX, localY) {
    var target = moduleClickTargetAt(slot, localX, localY)
    if (!target) return false

    target.triggerPress(button)
    return true
  }

  function colorHex(colorValue) {
    var c = colorValue
    if (typeof c === "string") c = Qt.color(c)
    function hexChannel(value) {
      var s = Math.round(Util.clamp(value, 0, 1) * 255).toString(16)
      return s.length < 2 ? "0" + s : s
    }
    return "#" + hexChannel(c.r) + hexChannel(c.g) + hexChannel(c.b)
  }

  function setRequestedTransparency(value) {
    var nextTransparent = value === true
    requestedTransparent = nextTransparent
    if (!nextTransparent) {
      foregroundAnimationEnabled = false
      useTransparentForeground = false
      transparent = false
      transparentForeground = themeForeground
      restoreForegroundAnimation()
      return
    }
    scheduleTransparentForegroundRefresh()
  }

  function restoreForegroundAnimation() {
    Qt.callLater(function() {
      Qt.callLater(function() { root.foregroundAnimationEnabled = true })
    })
  }

  function scheduleTransparentForegroundRefresh() {
    if (!requestedTransparent) {
      transparentForeground = themeForeground
      return
    }
    transparentForegroundTimer.restart()
  }

  function refreshTransparentForeground() {
    if (!requestedTransparent || transparentForegroundProc.running) return

    transparentForegroundProc.command = [
      "omarchy-bar-text-color",
      root.position,
      String(root.barSize),
      colorHex(root.themeForeground),
      colorHex(root.themeContrastForeground)
    ]
    transparentForegroundProc.running = true
  }

  onRequestedTransparentChanged: scheduleTransparentForegroundRefresh()
  onPositionChanged: scheduleTransparentForegroundRefresh()
  onThemeForegroundChanged: scheduleTransparentForegroundRefresh()
  onThemeContrastForegroundChanged: scheduleTransparentForegroundRefresh()

  Timer {
    id: transparentForegroundTimer
    interval: 120
    repeat: false
    onTriggered: root.refreshTransparentForeground()
  }

  Process {
    id: transparentForegroundProc
    stdout: SplitParser {
      onRead: function(line) {
        var value = String(line || "").trim()
        if (!/^#[0-9A-Fa-f]{6}$/.test(value)) return

        root.foregroundAnimationEnabled = false
        root.transparentForeground = value
        if (root.requestedTransparent) {
          root.useTransparentForeground = true
          root.transparent = true
        }
        root.restoreForegroundAnimation()
      }
    }
  }

  FileView {
    path: root.stateHome + "/omarchy/current"
    watchChanges: true
    printErrors: false
    onFileChanged: root.scheduleTransparentForegroundRefresh()
  }

  function runProcess(process) {
    if (!process.running)
      process.running = true
  }

  function showTooltip(target, text) {
    clearTooltip()

    if (!targetTooltipHovered(target) || !text) {
      tooltipRequest += 1
      return
    }

    var request = tooltipRequest + 1
    tooltipRequest = request
    pendingTooltipTarget = target
    pendingTooltipText = text

    Qt.callLater(function() {
      if (request !== tooltipRequest) return
      if (!targetTooltipHovered(pendingTooltipTarget)) {
        clearTooltip()
        return
      }
      tooltipTarget = pendingTooltipTarget
      tooltipText = pendingTooltipText
      pendingTooltipTarget = null
      pendingTooltipText = ""
      tooltipTimer.restart()
    })
  }

  function hideTooltip(target) {
    if (tooltipTarget !== target && pendingTooltipTarget !== target) return

    tooltipRequest += 1
    clearTooltip()
  }

  Timer {
    id: tooltipTimer
    interval: 400
    onTriggered: {
      if (root.targetTooltipHovered(root.tooltipTarget)) root.tooltipShown = true
      else root.clearTooltip()
    }
  }

  Timer {
    interval: 100
    running: root.tooltipShown
    repeat: true
    onTriggered: if (!root.targetTooltipHovered(root.tooltipTarget)) root.hideTooltip(root.tooltipTarget)
  }

  // Presence of the `bar-off` flag = bar hidden. Watching the parent toggles
  // directory because FileView can't observe a file that doesn't exist yet,
  // and the flag is created/removed by `omarchy-toggle-bar`.
  Process {
    id: barHiddenProbe
    running: true
    command: ["bash", "-c", "[[ -f $HOME/.local/state/omarchy/toggles/bar-off ]] && echo yes || echo no"]
    stdout: SplitParser { onRead: function(line) { root.barHidden = String(line).trim() === "yes" } }
  }
  // Presence of the `toptop-stay-open` flag = the notch must never fold. The
  // probe is deliberately inverted like `bar-off` reads: no flag is the stock
  // hover-to-unfold behaviour, a flag pins the bar open.
  Process {
    id: hoverRevealProbe
    running: true
    command: ["bash", "-c", "[[ -f $HOME/.local/state/omarchy/toggles/toptop-stay-open ]] && echo no || echo yes"]
    stdout: SplitParser { onRead: function(line) {
      root.hoverRevealEnabled = String(line).trim() === "yes"
      if (!root.hoverRevealEnabled) root.forceOpen()
    } }
  }
  FileView {
    path: root.home + "/.local/state/omarchy/toggles"
    watchChanges: true
    printErrors: false
    onFileChanged: {
      barHiddenProbe.running = true
      hoverRevealProbe.running = true
    }
  }

  // The directory watch can permanently stop delivering events after flag
  // changes land in quick succession, stranding the bar off screen until the
  // shell restarts. `omarchy-toggle-bar` nudges this after flipping the flag
  // so the probe re-reads it even when the watch has gone quiet.
  IpcHandler {
    target: "omarchy.bar"

    // Start rather than restart: a probe already in flight was launched by the
    // directory watch after the flag flipped, so its answer is current, and
    // killing it here can swallow the result entirely.
    function syncHidden(): void {
      barHiddenProbe.running = true
    }
    // The stay-open toggle nudges the same directory watch may have missed.
    function syncHoverFold(): void {
      hoverRevealProbe.running = true
    }
    // Diagnostic for verifying the fold logic over IPC without looking at the
    // screen: reveal is what the notch width keys off (1 = full width).
    function foldState(): string {
      return JSON.stringify({
        reveal: root.reveal,
        hoverRevealEnabled: root.hoverRevealEnabled,
        notchHovered: root.notchHovered,
        centerHoverRevealSuppressed: root.centerHoverRevealSuppressed
      })
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      BarPanel {
        required property var modelData

        screen: modelData
      }
    }
  }

  // nagualcode.toptop: the drag ghost stays — dragging a widget to reorder it
  // works exactly as upstream. The bar-move ghost that went with it does not.
  Variants {
    model: Quickshell.screens

    delegate: Component {
      DragGhostPanel {
        required property var modelData

        screen: modelData
        ghostScreen: modelData
      }
    }
  }

  component BarPanel: PanelWindow {
    id: barWindow

    // Hiding parks the bar just past its screen edge instead of unmapping it.
    // Unmapping frees the layer surface and the whole scene graph, so every
    // reveal has to rebuild them — new surface, re-shaped glyphs, re-uploaded
    // textures — which measures ~150ms against ~20ms to tear down. Parking
    // keeps the surface alive, so showing is only a margin change.
    visible: !remapGuard.remapping

    // nagualcode.toptop: the notch never claims screen space. Upstream uses
    // ExclusionMode.Auto, which reserves a strip as deep as the bar across the
    // whole screen width and pushes every window below it. A notch reserving
    // the full width would indent every window for a shape that covers a
    // fraction of it, and the whole point of the shape is that the desktop to
    // either side of it stays free — so the surface draws over the windows
    // instead, and the top of a maximized window is simply behind the notch.
    exclusionMode: ExclusionMode.Ignore

    ScreenMoveRemap {
      id: remapGuard
      window: barWindow
    }

    margins.top: root.barHidden ? -root.barSize : 0

    // The surface spans the screen so the notch can sit in the middle of it,
    // but it is only barSize tall and always flush with the top edge. Fixed
    // geometry, like upstream: the notch grows *within* the surface, so
    // unfolding it never resizes a layer surface.
    anchors {
      top: true
      left: true
      right: true
    }

    implicitWidth: 0
    implicitHeight: root.barSize
    color: "transparent"
    surfaceFormat.opaque: false

    // Only the notch takes input. A full-width surface would otherwise swallow
    // every click along the top strip of the screen — including on the windows
    // the free area exists to expose. Recomputed as the notch resizes, which
    // is what keeps the collapse from taking the pointer's own hover away.
    mask: Region { item: notchSurface }

    WlrLayershell.namespace: "omarchy-bar"
    WlrLayershell.layer: WlrLayer.Top

    // nagualcode.toptop: the notch.
    //
    // One centred block holding the three layout sections side by side with no
    // gap and nothing free between them, rounded at the bottom corners and
    // square at the top — a MacBook notch, not a full-width bar.
    //
    // Its width is the width of its content, so it is exactly as wide as the
    // icons it is currently showing: narrow around the clock and the battery,
    // and as wide as the full layout once unfolded. Everything to either side
    // is transparent surface with its input masked away.
    Item {
      id: notchSurface

      anchors.top: parent.top
      anchors.horizontalCenter: parent.horizontalCenter
      width: notchRow.implicitWidth
      height: root.barSize

      // A child of the surface, not a sibling of the sections: an ancestor stays
      // hovered while the pointer is over a widget, where a sibling would lose
      // hover to the group the pointer entered. Unfolding is driven from here,
      // so the pointer never has to reach past the collapsed notch to open it.
      HoverHandler {
        onHoveredChanged: root.setNotchHovered(hovered)
        // Unplugging a monitor destroys its bar without a leave event, which
        // would strand the hover and hold the notch open for good.
        Component.onDestruction: if (hovered) root.setNotchHovered(false)
      }

      NotchBackground {
        anchors.fill: parent
        cornerRadius: root.cornerRadius
        // With an empty centre there is nothing to draw while folded, and a
        // bare rounded shape hanging off the top edge reads as a glitch. Hidden
        // rather than zero-width, so the surface keeps the hover target and the
        // bar can still be unfolded to drag something back into the centre.
        visible: root.pinnedEntryCount > 0 || root.reveal > 0
      }

      // Behind the groups, so a click that lands on a widget is the widget's
      // and only empty notch space reaches this.
      NotchGestureArea { anchors.fill: parent }

      // Vertical centring only. `anchors.horizontalCenter` here would be a
      // binding loop: the row's width sets the surface's width, and the
      // surface's centre would set the row's x.
      Row {
        id: notchRow
        spacing: 0
        width: implicitWidth
        anchors.verticalCenter: parent.verticalCenter

        // --- left section, outermost first ---------------------------------
        Item {
          width: root.endPadding
          height: root.barSize
        }

        NotchGroup {
          region: "left"
          entries: root.notchGroups.left.outer
          pinnedEdge: 1
          share: root.reveal
        }

        NotchGroup {
          region: "left"
          entries: root.notchGroups.left.pinned
          pinnedEdge: 1
          share: 1
        }

        NotchGroup {
          region: "left"
          entries: root.notchGroups.left.inner
          pinnedEdge: 1
          share: root.reveal
        }

        // --- centre section, pinned around the clock ------------------------
        NotchGroup {
          region: "center"
          entries: root.notchGroups.center.outer
          pinnedEdge: 1
          share: root.reveal
        }

        NotchGroup {
          region: "center"
          entries: root.notchGroups.center.pinned
          pinnedEdge: 1
          share: 1
        }

        NotchGroup {
          region: "center"
          entries: root.notchGroups.center.inner
          pinnedEdge: -1
          share: root.reveal
        }

        // --- right section, innermost first --------------------------------
        NotchGroup {
          region: "right"
          entries: root.notchGroups.right.inner
          pinnedEdge: -1
          share: root.reveal
        }

        NotchGroup {
          region: "right"
          entries: root.notchGroups.right.pinned
          pinnedEdge: -1
          share: 1
        }

        NotchGroup {
          region: "right"
          entries: root.notchGroups.right.outer
          pinnedEdge: -1
          share: root.reveal
        }

        Item {
          width: root.endPadding
          height: root.barSize
        }
      }
    }

    PopupWindow {
      id: tooltipWindow

      visible: root.tooltipShown && root.tooltipTarget !== null && root.tooltipText !== "" && root.targetBelongsToWindow(root.tooltipTarget, barWindow)
      color: "transparent"
      implicitWidth: Math.ceil(tooltipBubble.implicitWidth)
      implicitHeight: Math.ceil(tooltipBubble.implicitHeight)

      anchor {
        id: tooltipAnchor
        window: barWindow
        adjustment: PopupAdjustment.Slide
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        rect.width: 1
        rect.height: 1

        onAnchoring: {
          var target = root.tooltipTarget
          if (!root.targetBelongsToWindow(target, barWindow)) return

          var popupWidth = tooltipWindow.implicitWidth
          var popupHeight = tooltipWindow.implicitHeight
          var localX = target.width / 2 - popupWidth / 2
          var localY = target.height + 6

          if (root.position === "bottom") {
            localY = -popupHeight - 6
          } else if (root.position === "left") {
            localX = target.width + 6
            localY = target.height / 2 - popupHeight / 2
          } else if (root.position === "right") {
            localX = -popupWidth - 6
            localY = target.height / 2 - popupHeight / 2
          }

          var point = barWindow.contentItem.mapFromItem(target, localX, localY)
          tooltipAnchor.rect.x = Math.round(point.x)
          tooltipAnchor.rect.y = Math.round(point.y)
        }
      }

      BorderSurface {
        id: tooltipBubble
        implicitWidth: tooltipLabel.implicitWidth + 20
        implicitHeight: tooltipLabel.implicitHeight + 14
        color: Color.tooltip.background
        borderSpec: Border.surfaceSpec("tooltip", "border", Color.tooltip.border, 1)
        radius: Style.cornerRadius

        Text {
          id: tooltipLabel
          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: root.tooltipText
          color: Color.tooltip.text
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }
      }
    }

    // nagualcode.toptop: upstream's `horizontalBar` and `verticalBar`
    // components are gone. The Loader that chose between them is replaced by
    // the notch, which is horizontal by construction — there is no vertical
    // bar to switch to, and position is pinned to "top".
  }

  Component { id: emptyModuleComponent; Item { implicitWidth: 0; implicitHeight: 0; visible: false } }

  component DragGhostPanel: PanelWindow {
    id: ghostWindow

    required property var ghostScreen
    readonly property bool screenMatches: root.barDragScreen === ghostScreen ||
      (root.barDragScreen && ghostScreen && root.barDragScreen.name && ghostScreen.name && root.barDragScreen.name === ghostScreen.name)
    readonly property bool active: root.barDragSource && root.barDragScreen && screenMatches
    readonly property var sourceItem: root.barDragSource ? root.barDragSource.activeItem : null
    readonly property int ghostPadding: Style.space(1)
    readonly property int ghostWidth: sourceItem ? Math.max(1, Math.ceil(sourceItem.width)) : 1
    readonly property int ghostHeight: sourceItem ? Math.max(1, Math.ceil(sourceItem.height)) : 1

    visible: active && sourceItem !== null
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-bar-drag-ghost"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    // Visual-only drag feedback. Keep the input region empty so the ghost can
    // sit under the cursor without stealing the MouseArea's active pointer grab.
    mask: Region {}

    Item {
      visible: ghostWindow.visible
      x: Math.round(root.barDragScreenX - root.barDragOffsetX - ghostWindow.ghostPadding)
      y: Math.round(root.barDragScreenY - root.barDragOffsetY - ghostWindow.ghostPadding)
      width: ghostWindow.ghostWidth + ghostWindow.ghostPadding * 2
      height: ghostWindow.ghostHeight + ghostWindow.ghostPadding * 2

      BorderSurface {
        anchors.fill: parent
        color: root.transparent ? "transparent" : root.background
        borderSpec: Border.flat(root.barForeground, 1)
        radius: Math.min(Style.cornerRadius, height / 2)
        opacity: root.transparent ? 0.45 : 0.94
      }

      Image {
        anchors.fill: parent
        anchors.margins: ghostWindow.ghostPadding
        source: root.barDragImageUrl
        fillMode: Image.Stretch
        smooth: true
        opacity: 0.84
      }
    }

    Rectangle {
      readonly property var targetRect: root.barDragTargetGeometry

      visible: ghostWindow.active && targetRect !== null
      x: targetRect ? Math.round(targetRect.x) : 0
      y: targetRect ? Math.round(targetRect.y) : 0
      width: targetRect ? targetRect.width : 0
      height: targetRect ? targetRect.height : 0
      color: Color.accent
      radius: Math.min(width, height) / 2
    }
  }

  // nagualcode.toptop: upstream's BarMoveGhostPanel is removed with the gesture
  // that drove it. See the note on the barMove* properties above.

  // nagualcode.toptop: the notch's background — square along the top edge,
  // rounded at the bottom corners, which is the shape a notch cut into the top
  // of a screen has.
  //
  // A Rectangle cannot do this: its radius applies to all four corners, and
  // squaring the top two off afterwards means painting over the rounded ones,
  // which cannot be done when the fill is transparent (the transparent bar is
  // an outline, and there is nothing to paint over it with). Shape draws the
  // outline once, so one path serves both the filled and the transparent bar.
  component NotchBackground: Shape {
    id: notchBackground

    property real cornerRadius: Style.cornerRadius

    // A corner can never take more than half the height, or the two bottom
    // arcs would meet and the shape would start growing upwards.
    readonly property real effectiveRadius: Math.max(0, Math.min(cornerRadius, height / 2, width / 2))

    anchors.fill: parent

    ShapePath {
      fillColor: root.transparent ? "transparent" : root.background
      strokeColor: root.transparent ? root.barForeground : "transparent"
      strokeWidth: 1

      PathSvg { path: notchBackground.outline() }
    }

    function outline() {
      var w = width
      var h = height
      var r = effectiveRadius

      if (w <= 0 || h <= 0) return "M 0 0 Z"
      if (r <= 0.5) return "M 0 0 L " + w + " 0 L " + w + " " + h + " L 0 " + h + " Z"

      // Top edge, straight down the right, round the bottom-right corner,
      // back along the bottom, round the bottom-left corner, and up. Sweep 1
      // is clockwise in Qt's y-down path space, which is the way round a
      // bottom corner.
      return "M 0 0"
        + " L " + w + " 0"
        + " L " + w + " " + (h - r)
        + " A " + r + " " + r + " 0 0 1 " + (w - r) + " " + h
        + " L " + r + " " + h
        + " A " + r + " " + r + " 0 0 1 0 " + (h - r)
        + " Z"
    }
  }

  // nagualcode.toptop: one run of the layout, inside the notch.
  //
  // `share` is the fraction of the run's natural width to show — 1 for the runs
  // that are always visible, root.reveal for the rest. Clipping a run that stays
  // mounted, rather than rebuilding it, is the point: a tray that remounts on
  // every hover drops its animations, and a clock that remounts restarts its
  // timer and can be caught mid-tick.
  component NotchGroup: Item {
    id: group

    property var entries: []
    property string region: ""
    property real share: 1
    // Which edge of this box the content holds to: 1 for a run left of the
    // centre, -1 for one right of it. A run grows away from the centre, so the
    // content stays pinned to the centre-facing edge and is uncovered from the
    // inside out — the icons appear next to the clock first, and the far ones
    // last, rather than the whole bar sliding in from off-screen.
    property int pinnedEdge: 1

    readonly property real naturalWidth: groupRow.implicitWidth

    width: Math.max(0, Math.round(naturalWidth * share))
    height: root.barSize
    // Deliberately never `visible: width > 0`. A run's width is derived from
    // its widgets, and QQuickItem reports *effective* visibility for an item
    // that declares no `visible` binding of its own. Hiding a collapsed run
    // therefore made every widget inside it read `visible === false`, which
    // zeroed the implicit widths that compute this width, which kept the run
    // hidden: the notch measured nothing but its end padding and drew as a
    // bare dot. Collapse through width and opacity instead, and clip whenever
    // the two ends do not coincide so a collapsed run neither paints nor takes
    // pointer input.
    clip: share < 1
    opacity: share

    Row {
      id: groupRow

      spacing: 0
      width: implicitWidth
      height: implicitHeight
      anchors.verticalCenter: parent.verticalCenter
      x: group.pinnedEdge > 0 ? group.width - width : 0

      Repeater {
        model: group.entries

        ModuleSlot {
          required property var modelData

          entry: modelData
          region: group.region
        }
      }
    }
  }

  // nagualcode.toptop: the notch's empty space.
  //
  // Upstream fills the whole centre section with this area and gives it two
  // jobs: dragging the bar to another screen edge, and double-clicking to
  // toggle transparency. A notch has no other edge, so only the double-click
  // survives.
  //
  // Right-click is spare, and is how the installed-widgets menu is reached. It
  // is handled here rather than per widget so that it answers on empty notch
  // space and on an icon alike.
  //
  // It fills the notch and is declared before the groups, so it sits behind
  // them: a click on an icon stays that icon's, and only a click on genuinely
  // empty notch space arrives here.
  component NotchGestureArea: MouseArea {
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    onDoubleClicked: function(mouse) {
      if (mouse.button === Qt.LeftButton) {
        root.toggleTransparency()
        mouse.accepted = true
      }
    }

    onPressed: function(mouse) {
      if (mouse.button !== Qt.RightButton) return

      root.manageWidgets()
      mouse.accepted = true
    }
  }

  // nagualcode.toptop: upstream's ModuleList is replaced by NotchGroup, which
  // adds the collapse/unfold clipping on top of the same job.

  component ModuleSlot: Item {
    id: slot

    required property var entry
    property string region: ""
    readonly property string moduleName: root.entryId(entry)
    readonly property var moduleSettings: root.entrySettings(entry)
    readonly property string customType: root.customModuleType(entry)
    readonly property var registryMetadata: root.barWidgetRegistry.metadataFor(root.canonicalWidgetId(moduleName))
    readonly property bool firstParty: registryMetadata && registryMetadata.firstParty === true
    readonly property string pluginApiId: registered ? root.canonicalWidgetId(moduleName) : "bar-entry:" + moduleName
    // Re-evaluate when the registry mutates (Component reference changes,
    // plugin enabled/disabled, etc.). Reading the `widgets` property creates
    // the binding dependency — the wrapped function call alone wouldn't.
    readonly property var registryComponent: {
      var w = root.barWidgetRegistry.widgets
      if (customType) return null
      var registryName = root.canonicalWidgetId(moduleName)
      return w[registryName] ? w[registryName].component : null
    }
    readonly property bool qmlCustom: customType === "qml"
    readonly property bool commandCustom: customType === "command"
    readonly property bool registered: registryComponent !== null
    readonly property var activeItem: {
      if (registered) return registryLoader.item
      if (qmlCustom) return qmlLoader.item
      return componentLoader.item
    }
    readonly property bool hovered: moduleHover.hovered
    readonly property bool dragSource: root.barDragSource === slot
    readonly property bool panelOpen: root.activePopout === slot.activeItem
    // Modules bigger than the mark they want (a text label in a padded slot,
    // a multi-line stack on a vertical bar) can say how long the open-panel
    // dot should be along the bar, so it tracks what the module paints
    // instead of a fraction of whatever slot it happens to fill.
    readonly property real panelIndicatorExtent: {
      var key = root.vertical ? "openPanelIndicatorHeight" : "openPanelIndicatorWidth"
      var hint = activeItem && key in activeItem ? activeItem[key] : undefined
      if (hint !== undefined && hint !== null && hint > 0) return Math.round(hint)
      return Math.max(Style.space(10), Math.round((root.vertical ? slot.height : slot.width) * 0.55))
    }
    implicitWidth: activeItem && activeItem.visible ? (root.vertical ? root.barSize : activeItem.implicitWidth) : 0
    implicitHeight: activeItem && activeItem.visible ? activeItem.implicitHeight : 0
    width: implicitWidth
    height: implicitHeight
    z: modulePointer.dragging ? 100 : 0

    Component.onCompleted: root.registerModuleSlot(slot)
    Component.onDestruction: {
      if (root.barDragSource === slot) root.clearBarDrag()
      root.unregisterModuleSlot(slot)
    }

    HoverHandler { id: moduleHover }

    BorderSurface {
      visible: slot.dragSource
      anchors.fill: parent
      anchors.margins: Style.space(1)
      color: root.transparent ? "transparent" : root.background
      borderSpec: Border.flat(root.barForeground, 1)
      radius: Math.min(Style.cornerRadius, height / 2)
      opacity: root.transparent ? 0.22 : 0.32
    }

    Loader {
      id: componentLoader
      active: !slot.qmlCustom && !slot.registered
      sourceComponent: slot.commandCustom ? customCommandModuleComponent : emptyModuleComponent
      anchors.fill: parent
      opacity: slot.dragSource ? 0.22 : 1.0
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Loader {
      id: registryLoader
      active: slot.registered
      sourceComponent: slot.registered ? slot.registryComponent : null
      anchors.fill: parent
      opacity: slot.dragSource ? 0.22 : 1.0
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Loader {
      id: qmlLoader
      active: slot.qmlCustom
      source: slot.qmlCustom ? root.customModuleSource(slot.entry) : ""
      anchors.fill: parent
      opacity: slot.dragSource ? 0.22 : 1.0
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Rectangle {
      id: openPanelIndicator

      readonly property int inset: Style.space(2)

      visible: opacity > 0
      opacity: slot.panelOpen && !slot.dragSource ? 0.9 : 0
      color: Color.accent
      radius: Math.min(width, height) / 2
      width: root.vertical ? Style.space(2) : slot.panelIndicatorExtent
      height: root.vertical ? slot.panelIndicatorExtent : Style.space(2)
      // The mark sits on the module's inner edge — the one facing the
      // desktop — so it underlines a top bar, overlines a bottom one, and
      // points inward from a left or right one. It reads as pointing at the
      // panel that opens on that side.
      x: root.vertical
        ? (root.position === "left" ? parent.width - width - inset : inset)
        : Math.round((parent.width - width) / 2)
      y: root.vertical
        ? Math.round((parent.height - height) / 2)
        : (root.position === "top" ? parent.height - height - inset : inset)
      z: 50

      Behavior on opacity {
        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
      }
    }

    MouseArea {
      id: modulePointer

      property bool dragging: false
      property bool suppressClick: false
      property real pressedX: 0
      property real pressedY: 0
      readonly property bool canReorder: root.shell && typeof root.shell.mutateShellConfig === "function"
      readonly property real dragThreshold: Style.space(4)

      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      enabled: slot.visible && slot.width > 0 && slot.height > 0
      propagateComposedEvents: true
      cursorShape: root.moduleClickTargetAt(slot, mouseX, mouseY) ? Qt.PointingHandCursor : Qt.ArrowCursor
      // Do not assign drag.target here: ModuleSlot is owned by Row/Column
      // positioners, and mutating slot.x/slot.y can leave stale offsets that
      // make neighboring modules overlap after a small aborted drag.

      onPressed: function(mouse) {
        dragging = false
        suppressClick = false
        pressedX = mouse.x
        pressedY = mouse.y
        root.clearBarDrag()
      }

      onPositionChanged: function(mouse) {
        if (!canReorder || !(mouse.buttons & Qt.LeftButton)) return

        var distance = Math.abs(mouse.x - pressedX) + Math.abs(mouse.y - pressedY)
        if (distance >= dragThreshold) {
          if (!dragging) {
            root.barDragWindow = root.targetWindow(slot.activeItem) || root.targetWindow(slot)
            root.barDragScreen = root.barDragWindow ? root.barDragWindow.screen : null
            root.barDragOffsetX = pressedX
            root.barDragOffsetY = pressedY
            root.captureBarDragGhost(slot)
            root.barDragSource = slot
          }
          dragging = true
          root.hideTooltip(slot.activeItem)
        }

        if (dragging) {
          var scenePoint = slot.mapToItem(null, mouse.x, mouse.y)
          var screenPoint = root.barDragScreenPoint(scenePoint)
          root.barDragSceneX = scenePoint.x
          root.barDragSceneY = scenePoint.y
          root.barDragScreenX = screenPoint.x
          root.barDragScreenY = screenPoint.y

          var drop = root.moduleDropAtScene(scenePoint, slot)
          root.barDragTarget = drop ? drop.slot : null
          root.barDragAfter = drop ? drop.after : false
          root.barDragTargetGeometry = drop ? root.dropMarkerRect(drop.slot, drop.after) : null
        }
      }

      onReleased: function(mouse) {
        var wasDragging = dragging
        var targetSlot = root.barDragTarget
        var afterTarget = root.barDragAfter

        if (wasDragging) suppressClick = true

        dragging = false
        root.clearBarDrag()

        if (wasDragging && targetSlot) {
          root.dropBarModuleAtTarget(slot, targetSlot, afterTarget)
          mouse.accepted = true
        } else if (!wasDragging) {
          mouse.accepted = false
        }
      }

      onCanceled: {
        dragging = false
        suppressClick = false
        root.clearBarDrag()
      }

      onClicked: function(mouse) {
        if (suppressClick) {
          suppressClick = false
          mouse.accepted = true
          return
        }

        if (!root.pressModuleClickTarget(slot, mouse.button, mouse.x, mouse.y)) mouse.accepted = false
      }
    }

    onActiveItemChanged: Qt.callLater(injectProps)
    onModuleSettingsChanged: injectProps()

    function injectProps() {
      var target = activeItem
      if (!target) return

      // Assigning the host is the one step here that can come back empty: a
      // third-party widget whose plugin is not in the registry has no API
      // object, and a slot can also be torn down between the change being
      // queued (Qt.callLater) and this running, by which point `root` is gone.
      // The bare assignment threw on undefined, which not only lost the host
      // but aborted the rest of the function, so moduleName and settings went
      // uninjected too. Fail this one step and carry on with the others.
      if ("bar" in target && root) {
        var api = firstParty ? root : root.pluginBarApiFor(pluginApiId, moduleName, registered)
        if (api) target.bar = api
      }
      if ("moduleName" in target) target.moduleName = moduleName
      if ("settings" in target) target.settings = moduleSettings
    }

    Component {
      id: customCommandModuleComponent
      CustomCommandModule { entry: slot.entry }
    }
  }

  component CustomCommandModule: WidgetButton {
    id: customRoot

    required property var entry
    readonly property string moduleName: root.entryId(entry)
    readonly property var settings: root.entrySettings(entry)
    property string outputText: ""
    property string outputTooltip: ""
    property bool outputActive: false

    function setting(name, fallback) {
      var value = settings ? settings[name] : undefined
      return value === undefined || value === null ? fallback : value
    }

    function update(raw) {
      var data = Util.parseModuleJson(raw)
      var klass = data.class || data.alt || ""

      outputText = data.text || String(raw || "").trim()
      outputTooltip = data.tooltip || String(setting("tooltip", ""))
      outputActive = klass === "active" || (Array.isArray(klass) && klass.indexOf("active") !== -1)
    }

    bar: root
    text: outputText || String(setting("text", ""))
    tooltipText: outputTooltip || String(setting("tooltip", ""))
    active: outputActive
    keepSpace: setting("keepSpace", false) === true
    horizontalMargin: Number(setting("horizontalMargin", 7.5))
    verticalPadding: Number(setting("verticalPadding", 6))
    fontSize: Number(setting("fontSize", 12))

    onPressed: function(button) {
      var command = ""
      if (button === Qt.RightButton)
        command = String(setting("onRightClick", ""))
      else if (button === Qt.MiddleButton)
        command = String(setting("onMiddleClick", ""))
      else
        command = String(setting("onClick", ""))

      if (command) root.run(command)
    }

    Process {
      id: customProc
      command: ["bash", "-lc", String(customRoot.setting("exec", ""))]
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: customRoot.update(text)
      }
    }

    Timer {
      interval: Math.max(1, Number(customRoot.setting("interval", 5))) * 1000
      running: String(customRoot.setting("exec", "")) !== ""
      repeat: true
      triggeredOnStart: true
      onTriggered: root.runProcess(customProc)
    }
  }
}
