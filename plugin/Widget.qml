import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// GlobalProtect flow:
// left-click -> if connected, show the session; otherwise
// gateway -> validate gateway -> username/password -> validate credentials
// -> connected. Successful credentials are stored in the desktop keyring
// through gp-vpn-credentials.
//
// Status is polled rather than tracked from this widget's own actions: the
// tunnel can be brought up or torn down outside the UI (a terminal run, a
// dropped session), and the widget must reflect that.
Panel {
  id: root
  moduleName: "bol.gpvpn"
  ipcTarget: "bol.gpvpn"

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal

  readonly property string configuredGateway: String(setting("gpGateway", "")).trim()
  property string gateway: configuredGateway
  property string username: ""
  property string password: ""
  property string pendingPassword: ""
  property string errorText: ""
  property string statusText: ""
  property string flow: "closed"
  property bool connected: false
  property bool busy: false
  property int connectElapsedSecs: 0
  property int cooldownSecs: 0
  property int spinnerFrame: 0
  readonly property var spinnerFrames: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
  readonly property string spinnerGlyph: spinnerFrames[spinnerFrame % spinnerFrames.length]

  readonly property string title: flow === "gateway" ? "GlobalProtect VPN"
    : (flow === "connected" ? "VPN Connected" : "GlobalProtect Login")

  // Tab would otherwise walk focus out of this layer-shell surface (the panel
  // then stops receiving keys entirely), so every focusable control in the
  // current step moves focus explicitly instead of relying on the default
  // chain. Order follows visual layout: fields, then primary action, then
  // Close, wrapping back to the first field.
  function focusNext(backwards) {
    var order = (flow === "gateway") ? [gatewayInput, primaryButton, closeButton]
      : [usernameInput, passwordInput, primaryButton, closeButton]
    var current = order.indexOf(activeFocusItem())
    var next = current < 0 ? 0 : (current + (backwards ? -1 : 1) + order.length) % order.length
    order[next].forceActiveFocus()
  }

  function activeFocusItem() {
    if (gatewayInput.activeFocus) return gatewayInput
    if (usernameInput.activeFocus) return usernameInput
    if (passwordInput.activeFocus) return passwordInput
    if (primaryButton.activeFocus) return primaryButton
    if (closeButton.activeFocus) return closeButton
    return null
  }

  // In the connected view the primary action is Disconnect, so a live session
  // always has an obvious way out. When cooling down, show a countdown label.
  readonly property string primaryLabel: flow === "connected" ? "Disconnect"
    : (flow === "gateway" ? "Check Gateway"
    : (root.cooldownSecs > 0 ? "Wait (" + root.cooldownSecs + "s)" : "Connect"))

  function primaryAction() {
    if (root.cooldownSecs > 0) return
    if (flow === "connected") disconnect()
    else if (flow === "gateway") startGatewayCheck()
    else startLogin()
  }

  // KeyboardPanel primes layer-shell focus when it maps; Qt focus has to be
  // handed to a child afterwards, once layout has run.
  function focusGatewayInput() {
    Qt.callLater(function() { gatewayInput.forceActiveFocus() })
  }

  function focusUsernameInput() {
    Qt.callLater(function() { usernameInput.forceActiveFocus() })
  }

  // Left-click: an established session gets its own view (with Disconnect),
  // otherwise the connect flow starts.
  function open() {
    errorText = ""
    statusText = ""
    if (connected) {
      flow = "connected"
      statusText = "Connected to " + (sessionGateway() || gateway || "the VPN")
    } else if (connectProcess.running) {
      flow = "connecting"
      statusText = "Waiting for authenticator approval... (approve once, " + connectElapsedSecs + "s)"
    } else {
      gateway = configuredGateway
      flow = "gateway"
      statusText = ""
      // If no gateway is configured in the widget settings, fall back to the
      // one remembered from the last successful validation, so it does not have
      // to be typed again.
      if (gateway === "") loadSavedGateway()
    }
    controller.show()
    if (flow === "gateway") focusGatewayInput()
  }

  function close() {
    controller.hide()
    if (!connectProcess.running) {
      flow = "closed"
      busy = false
    }
  }

  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    close()
    Qt.callLater(function() { popoutSwitchClosing = false })
  }

  function openFlow() { open() }
  function closeFlow() { close() }

  // The gateway actually in use, read from the running openconnect process so
  // a session started outside this widget still reports its real endpoint.
  function sessionGateway() {
    return String(sessionInfo.text || "").trim()
  }

  function startGatewayCheck() {
    gateway = gatewayInput.text.trim()
    errorText = ""
    if (gateway === "") {
      errorText = "Enter a gateway address."
      return
    }
    busy = true
    statusText = "Checking gateway connection..."
    gatewayCheck.command = ["gp-vpn-gateway-check", gateway]
    gatewayCheck.running = true
  }

  function loadSavedCredentials() {
    savedUserProcess.command = ["gp-vpn-credentials", "get-user", gateway]
    savedPasswordProcess.command = ["gp-vpn-credentials", "get-password", gateway]
    savedUserProcess.running = true
    savedPasswordProcess.running = true
  }

  // The remembered gateway, used when the widget setting is empty so the
  // address survives across sessions the way the credentials do.
  function loadSavedGateway() {
    savedGatewayProcess.running = true
  }

  function showCredentials() {
    busy = false
    statusText = "Gateway is reachable. Enter your GlobalProtect credentials."
    flow = "credentials"
    // Remember the gateway the same way credentials are remembered, so it only
    // has to be typed once; the stored value is loaded on open when the shell
    // setting is empty.
    saveGateway.command = ["gp-vpn-credentials", "save-gateway", gateway]
    saveGateway.running = true
    loadSavedCredentials()
    focusUsernameInput()
  }

  function startLogin() {
    // Re-entry guard. Without it, every click on Connect starts a *new*
    // gp-vpn-connect, and each of those submits its own credential POST, i.e.
    // one more authenticator push. Also blocked during post-timeout cooldown
    // to allow backend sessions to expire.
    if (busy || connectProcess.running || root.cooldownSecs > 0) return
    username = usernameInput.text.trim()
    password = passwordInput.text
    pendingPassword = password
    errorText = ""
    if (username === "" || password === "") {
      errorText = "Enter both username and password."
      return
    }
    busy = true
    flow = "connecting"
    connectElapsedSecs = 0
    statusText = "Validating username and password..."
    connectProcess.command = ["gp-vpn-connect", gateway, username]
    connectProcess.running = true
  }

  function connectionSucceeded() {
    busy = false
    flow = "connected"
    statusText = "Connected to " + gateway
    // The poll will also pick this up, but setting it now keeps the bar icon
    // from lagging behind the panel.
    connected = true
    root.cooldownSecs = 0
    saveCredentials.command = ["gp-vpn-credentials", "save-password", gateway, username, pendingPassword]
    saveCredentials.running = true
  }

  function connectionFailed(message) {
    busy = false
    flow = "credentials"
    pendingPassword = ""
    errorText = message || "Username or password was rejected."
    refreshStatus()
  }

  function disconnect() {
    errorText = ""
    busy = true
    statusText = "Disconnecting..."
    disconnectProcess.running = true
  }

  function refreshStatus() {
    statusProcess.running = true
    sessionProcess.running = true
  }

  Component.onCompleted: refreshStatus()

  // Poll on a timer as well: the tunnel can go down on its own (network
  // change, server-side timeout) with no widget action to observe.
  Timer {
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshStatus()
  }

  // Drives the spinner glyph and the elapsed-time counter while a connect
  // attempt is in flight, so a long authenticator-approval wait has visible
  // progress instead of looking frozen for up to a minute.
  Timer {
    interval: 200
    running: root.flow === "connecting"
    repeat: true
    onTriggered: {
      root.spinnerFrame = root.spinnerFrame + 1
      if (root.spinnerFrame % 5 === 0) {
        root.connectElapsedSecs = root.connectElapsedSecs + 1
        if (root.connectElapsedSecs >= 3) {
          root.statusText = "Waiting for authenticator approval... (approve once, " + root.connectElapsedSecs + "s)"
        }
      }
    }
  }

  // Cooldown timer after a timeout/cancel to allow backend authentication
  // sessions on the gateway/RADIUS server to expire, preventing duplicate push spam.
  Timer {
    id: cooldownTimer
    interval: 1000
    repeat: true
    running: root.cooldownSecs > 0
    onTriggered: {
      root.cooldownSecs = root.cooldownSecs - 1
      if (root.cooldownSecs > 0) {
        root.statusText = "Waiting for server session to clear... (" + root.cooldownSecs + "s)"
      } else {
        root.errorText = ""
        root.statusText = "Ready to connect. Please approve only once when prompted."
      }
    }
  }

  Process {
    id: statusProcess
    command: ["gp-vpn-status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.connected = String(text || "").trim() === "connected"
    }
  }

  // Which gateway the live session is using, for display in the connected view.
  Process {
    id: sessionProcess
    command: ["bash", "-c", "pgrep -af openconnect | grep -oE '[^ ]+\\.(id|com|net|org|local)( |$)' | head -1 | tr -d ' '"]
    stdout: StdioCollector { id: sessionInfo; waitForEnd: true }
  }

  Process {
    id: gatewayCheck
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(code) {
      if (code === 0) root.showCredentials()
      else {
        root.busy = false
        root.errorText = "Gateway validation failed. Check the address or network."
        root.statusText = ""
      }
    }
  }

  Process {
    id: savedUserProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var value = String(text || "").trim()
        if (value !== "") root.username = value
        usernameInput.text = root.username
      }
    }
  }

  Process {
    id: savedPasswordProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // Trim the trailing newline only; a password may contain spaces.
        root.password = String(text || "").replace(/\n$/, "")
        passwordInput.text = root.password
      }
    }
  }

  Process {
    id: connectProcess
    stdinEnabled: true
    onStarted: {
      write(root.pendingPassword + "\n")
      root.password = ""
    }
    stderr: StdioCollector { waitForEnd: true }
    stdout: StdioCollector { waitForEnd: true }
    onExited: function(code) {
      if (code === 0) root.connectionSucceeded()
      else if (code === 3) {
        // A session was already up; reflect it instead of reporting failure.
        root.busy = false
        root.connected = true
        root.flow = "connected"
        root.statusText = "Already connected to " + root.gateway
        root.refreshStatus()
      }
      else if (code === 4) root.connectionFailed("Wrong username or password.")
      else if (code === 5) root.connectionFailed("Gateway is unreachable.")
      else if (code === 6) {
        root.cooldownSecs = 10
        root.connectionFailed("Approval timed out. Please wait 10s before trying again...")
      }
      else if (code === 7) root.connectionFailed("Password prompt was not confirmed. Press Connect and confirm it.")
      else root.connectionFailed("Connection failed (code " + code + ").")
    }
  }

  Process {
    id: saveCredentials
    stdout: StdioCollector { waitForEnd: true }
  }

  // Gateway remembered from the last successful validation (keyring), used to
  // prefill the address field when the widget setting is empty.
  Process {
    id: savedGatewayProcess
    command: ["gp-vpn-credentials", "get-gateway"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var value = String(text || "").trim()
        if (value !== "") {
          root.gateway = value
          gatewayInput.text = value
        }
      }
    }
  }

  Process {
    id: saveGateway
    stdout: StdioCollector { waitForEnd: true }
  }

  Process {
    id: disconnectProcess
    command: ["gp-vpn-disconnect"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.busy = false
        root.connected = false
        root.closeFlow()
        root.refreshStatus()
      }
    }
  }

  // Traverses the bar window scene graph to collect all active clickable targets (e.g.
  // Bluetooth, Wi-Fi, Audio buttons). This bridges the gap for third-party plugins where
  // PluginBarApi.clickTargets is scoped only to this plugin, allowing 1-click switching.
  function getBarClickTargets() {
    var win = button ? (button.QsWindow ? button.QsWindow.window : null) : null
    if (!win || !win.contentItem) {
      return (root.bar && root.bar.clickTargets) ? root.bar.clickTargets : []
    }
    var targets = []
    function walk(item) {
      if (!item) return
      if (typeof item.triggerPress === "function" && item.visible !== false && item.opacity > 0) {
        targets.push(item)
      }
      var children = item.children
      if (children && children.length) {
        for (var i = 0; i < children.length; i++) {
          walk(children[i])
        }
      }
    }
    try {
      walk(win.contentItem)
    } catch (e) {
      // Ignore traversal error and fall back
    }
    return targets.length > 0 ? targets : ((root.bar && root.bar.clickTargets) ? root.bar.clickTargets : [])
  }

  QtObject {
    id: barProxy

    readonly property color foreground: root.bar ? root.bar.foreground : "transparent"
    readonly property color barForeground: root.bar ? root.bar.barForeground : "transparent"
    readonly property color background: root.bar ? root.bar.background : "transparent"
    readonly property color urgent: root.bar ? root.bar.urgent : "transparent"
    readonly property string fontFamily: root.bar ? root.bar.fontFamily : ""
    readonly property string position: root.bar ? root.bar.position : "top"
    readonly property bool vertical: root.bar ? root.bar.vertical : false
    readonly property int barSize: root.bar ? root.bar.barSize : 0
    readonly property var activePopout: root.bar ? root.bar.activePopout : null

    readonly property var clickTargets: root.getBarClickTargets()

    function targetBelongsToWindow(target, window) {
      if (root.bar && typeof root.bar.targetBelongsToWindow === "function") {
        return root.bar.targetBelongsToWindow(target, window)
      }
      return !!target && !!window && target.QsWindow && target.QsWindow.window === window
    }

    function requestPopout(owner) {
      if (root.bar && typeof root.bar.requestPopout === "function") {
        root.bar.requestPopout(owner)
      }
    }

    function releasePopout(owner) {
      if (root.bar && typeof root.bar.releasePopout === "function") {
        root.bar.releasePopout(owner)
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "VPN"
    labelVisible: true
    fontSize: Style.font.caption
    slotSize: Style.bar.statusSlot
    active: root.connected
    activeColor: Color.accent
    tooltipText: root.connected ? "GlobalProtect: connected (click for details)" : "GlobalProtect: click to connect"
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton) {
        if (root.opened) root.close()
        else root.open()
      }
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: button
    bar: barProxy
    owner: root
    open: root.opened
    focusTarget: focusCatcher
    contentWidth: Style.space(360)
    // KeyboardPanel applies contentHeight as a FIXED card height, so a
    // hardcoded value clips the button row on longer steps. Size it from the
    // column's real height instead (the pattern Omarchy's own panels use).
    contentHeight: popup.fittedContentHeight(contentColumn.implicitHeight + Style.space(4))

    Keys.onEscapePressed: function(event) {
      root.close()
      event.accepted = true
    }

    // PopupCard (xdg-popup) never receives keys, so text fields inside it
    // can't be typed into. KeyboardPanel primes layer-shell keyboard focus
    // and needs an active-focus target inside the surface; this Item is it.
    // Keys pass through to the TextInput children (no Keys handlers here).
    Item {
      id: focusCatcher
      anchors.fill: parent
      focus: true
      activeFocusOnTab: false

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.close()
          event.accepted = true
          return
        }
      }
      Keys.onEscapePressed: function(event) {
        root.close()
        event.accepted = true
      }

      Column {
        id: contentColumn
        width: parent.width
        spacing: Style.space(6)

      Text {
        text: root.title
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
      }

      Text {
        visible: root.statusText !== ""
        text: (root.flow === "connecting" ? root.spinnerGlyph + "  " : "") + root.statusText
        color: Color.muted
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
        width: parent.width
      }

      // ---- connected view -------------------------------------------------
      Text {
        visible: root.flow === "connected"
        text: "Your traffic is routed through the GlobalProtect gateway."
        color: Color.muted
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
        width: parent.width
      }

      // ---- gateway step ---------------------------------------------------
      Text {
        visible: root.flow === "gateway"
        text: "Gateway address"
        color: Color.muted
        font.pixelSize: Style.font.bodySmall
      }

      TextInput {
        id: gatewayInput
        visible: root.flow === "gateway"
        width: parent.width
        height: Style.space(34)
        leftPadding: Style.space(8)
        verticalAlignment: TextInput.AlignVCenter
        text: root.gateway
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        selectByMouse: true
        clip: true
        Rectangle {
          anchors.fill: parent
          color: "transparent"
          border.color: Color.popups.border
          border.width: 1
          radius: Style.cornerRadius
          z: -1
        }
        Keys.onReturnPressed: root.startGatewayCheck()
        Keys.onTabPressed: function(event) { root.focusNext(false); event.accepted = true }
        Keys.onBacktabPressed: function(event) { root.focusNext(true); event.accepted = true }
        Keys.onEscapePressed: function(event) { root.close(); event.accepted = true }
      }

      // ---- credentials step -----------------------------------------------
      Text {
        visible: root.flow === "credentials" || root.flow === "connecting"
        text: "Username"
        color: Color.muted
        font.pixelSize: Style.font.bodySmall
      }

      TextInput {
        id: usernameInput
        visible: root.flow === "credentials" || root.flow === "connecting"
        width: parent.width
        height: Style.space(34)
        leftPadding: Style.space(8)
        verticalAlignment: TextInput.AlignVCenter
        text: root.username
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        selectByMouse: true
        clip: true
        Rectangle {
          anchors.fill: parent
          color: "transparent"
          border.color: Color.popups.border
          border.width: 1
          radius: Style.cornerRadius
          z: -1
        }
        Keys.onTabPressed: function(event) { root.focusNext(false); event.accepted = true }
        Keys.onBacktabPressed: function(event) { root.focusNext(true); event.accepted = true }
        Keys.onReturnPressed: root.focusNext(false)
        Keys.onEscapePressed: function(event) { root.close(); event.accepted = true }
      }

      Text {
        visible: root.flow === "credentials" || root.flow === "connecting"
        text: "Password"
        color: Color.muted
        font.pixelSize: Style.font.bodySmall
      }

      TextInput {
        id: passwordInput
        visible: root.flow === "credentials" || root.flow === "connecting"
        width: parent.width
        height: Style.space(34)
        leftPadding: Style.space(8)
        verticalAlignment: TextInput.AlignVCenter
        text: root.password
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        echoMode: TextInput.Password
        passwordCharacter: "•"
        selectByMouse: true
        clip: true
        Rectangle {
          anchors.fill: parent
          color: "transparent"
          border.color: Color.popups.border
          border.width: 1
          radius: Style.cornerRadius
          z: -1
        }
        Keys.onReturnPressed: root.startLogin()
        Keys.onTabPressed: function(event) { root.focusNext(false); event.accepted = true }
        Keys.onBacktabPressed: function(event) { root.focusNext(true); event.accepted = true }
        Keys.onEscapePressed: function(event) { root.close(); event.accepted = true }
      }

      Text {
        visible: root.errorText !== ""
        text: root.errorText
        color: Color.urgent
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
        width: parent.width
      }

      Row {
        spacing: Style.space(8)
        topPadding: Style.space(4)
        visible: root.flow !== "closed"

        // ---- primary button ---------------------------------------------
        // In the connected view the primary action is Disconnect, so a live
        // session always has an obvious way out.
        Rectangle {
          id: primaryButton
          width: Style.space(120)
          height: Style.space(32)
          radius: Style.cornerRadius
          color: root.flow === "connected" ? Color.urgent : (root.cooldownSecs > 0 || root.busy ? Color.muted : Color.accent)
          border.color: Color.popups.text
          border.width: activeFocus ? 2 : 0
          activeFocusOnTab: false
          focus: false
          Keys.onReturnPressed: root.primaryAction()
          Keys.onSpacePressed: root.primaryAction()
          Keys.onTabPressed: function(event) { root.focusNext(false); event.accepted = true }
          Keys.onBacktabPressed: function(event) { root.focusNext(true); event.accepted = true }
          Keys.onEscapePressed: function(event) { root.close(); event.accepted = true }
          Text {
            anchors.centerIn: parent
            text: root.primaryLabel
            color: Color.background
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
          MouseArea {
            anchors.fill: parent
            enabled: !root.busy && root.cooldownSecs <= 0
            cursorShape: (root.busy || root.cooldownSecs > 0) ? Qt.ArrowCursor : Qt.PointingHandCursor
            onClicked: {
              primaryButton.forceActiveFocus()
              root.primaryAction()
            }
          }
        }

        Rectangle {
          id: closeButton
          width: Style.space(80)
          height: Style.space(32)
          radius: Style.cornerRadius
          color: "transparent"
          border.color: activeFocus ? Color.popups.text : Color.popups.border
          border.width: activeFocus ? 2 : 1
          activeFocusOnTab: false
          focus: false
          Keys.onReturnPressed: root.close()
          Keys.onSpacePressed: root.close()
          Keys.onTabPressed: function(event) { root.focusNext(false); event.accepted = true }
          Keys.onBacktabPressed: function(event) { root.focusNext(true); event.accepted = true }
          Keys.onEscapePressed: function(event) { root.close(); event.accepted = true }
          Text {
            anchors.centerIn: parent
            text: "Close"
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              closeButton.forceActiveFocus()
              root.close()
            }
          }
        }
      }
      }
    }
  }
}
