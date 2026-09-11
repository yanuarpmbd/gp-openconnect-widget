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
BarWidget {
  id: root
  moduleName: "bol.gpvpn"

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

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

  readonly property string title: flow === "gateway" ? "GlobalProtect VPN"
    : (flow === "connected" ? "VPN Connected" : "GlobalProtect Login")

  // Tab would otherwise walk focus out of this layer-shell surface (the panel
  // then stops receiving keys entirely), so each field moves focus explicitly.
  function focusNext(backwards) {
    var order = (flow === "gateway") ? [gatewayInput]
      : [usernameInput, passwordInput]
    var current = order.indexOf(activeFocusItem())
    var next = current < 0 ? 0 : (current + (backwards ? -1 : 1) + order.length) % order.length
    order[next].forceActiveFocus()
  }

  function activeFocusItem() {
    if (gatewayInput.activeFocus) return gatewayInput
    if (usernameInput.activeFocus) return usernameInput
    if (passwordInput.activeFocus) return passwordInput
    return null
  }

  // In the connected view the primary action is Disconnect, so a live session
  // always has an obvious way out.
  readonly property string primaryLabel: flow === "connected" ? "Disconnect"
    : (flow === "gateway" ? "Check Gateway" : "Connect")

  function primaryAction() {
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
  function openFlow() {
    errorText = ""
    statusText = ""
    if (connected) {
      flow = "connected"
      statusText = "Connected to " + (sessionGateway() || gateway || "the VPN")
    } else {
      gateway = configuredGateway
      flow = "gateway"
      statusText = ""
    }
    popup.open = true
    if (flow === "gateway") focusGatewayInput()
  }

  // The gateway actually in use, read from the running openconnect process so
  // a session started outside this widget still reports its real endpoint.
  function sessionGateway() {
    return String(sessionInfo.text || "").trim()
  }

  function closeFlow() {
    popup.open = false
    flow = "closed"
    busy = false
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

  function showCredentials() {
    busy = false
    statusText = "Gateway is reachable. Enter your GlobalProtect credentials."
    flow = "credentials"
    loadSavedCredentials()
    focusUsernameInput()
  }

  function startLogin() {
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
    statusText = "Validating username and password..."
    connectProcess.command = ["gp-vpn-connect", gateway, username, password]
    connectProcess.running = true
  }

  function connectionSucceeded() {
    busy = false
    flow = "connected"
    statusText = "Connected to " + gateway
    // The poll will also pick this up, but setting it now keeps the bar icon
    // from lagging behind the panel.
    connected = true
    saveCredentials.command = ["gp-vpn-credentials", "save-password", gateway, username, pendingPassword]
    saveCredentials.running = true
  }

  function connectionFailed(message) {
    busy = false
    flow = "credentials"
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
      else root.connectionFailed("Connection failed (code " + code + ").")
    }
  }

  Process {
    id: saveCredentials
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
      if (mouseButton === Qt.LeftButton) root.openFlow()
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: false
    focusTarget: focusCatcher
    contentWidth: Style.space(360)
    // KeyboardPanel applies contentHeight as a FIXED card height, so a
    // hardcoded value clips the button row on longer steps. Size it from the
    // column's real height instead (the pattern Omarchy's own panels use).
    contentHeight: popup.fittedContentHeight(contentColumn.implicitHeight + Style.space(4))

    // PopupCard (xdg-popup) never receives keys, so text fields inside it
    // can't be typed into. KeyboardPanel primes layer-shell keyboard focus
    // and needs an active-focus target inside the surface; this Item is it.
    // Keys pass through to the TextInput children (no Keys handlers here).
    Item {
      id: focusCatcher
      anchors.fill: parent
      focus: true
      activeFocusOnTab: false

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
        text: root.statusText
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
        Keys.onTabPressed: root.focusNext(false)
        Keys.onBacktabPressed: root.focusNext(true)
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
        Keys.onTabPressed: root.focusNext(false)
        Keys.onBacktabPressed: root.focusNext(true)
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
          width: Style.space(120)
          height: Style.space(32)
          radius: Style.cornerRadius
          color: root.flow === "connected" ? Color.urgent : Color.accent
          Text {
            anchors.centerIn: parent
            text: root.primaryLabel
            color: Color.background
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
          MouseArea {
            anchors.fill: parent
            enabled: !root.busy
            cursorShape: Qt.PointingHandCursor
            onClicked: root.primaryAction()
          }
        }

        Rectangle {
          width: Style.space(80)
          height: Style.space(32)
          radius: Style.cornerRadius
          color: "transparent"
          border.color: Color.popups.border
          border.width: 1
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
            onClicked: root.closeFlow()
          }
        }
      }
      }
    }
  }
}
