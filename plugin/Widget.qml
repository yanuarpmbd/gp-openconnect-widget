import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// GlobalProtect flow:
// left-click -> gateway -> validate gateway -> username/password ->
// validate credentials -> connected. Successful credentials are stored in
// the desktop keyring through gp-vpn-credentials.
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

  readonly property string primaryLabel: flow === "gateway" ? "Check Gateway"
    : (flow === "connected" ? "Close" : "Connect")

  function primaryAction() {
    if (flow === "gateway") startGatewayCheck()
    else if (flow === "connected") closeFlow()
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

  function openFlow() {
    if (connected) {
      disconnectProcess.running = true
      return
    }
    gateway = configuredGateway
    errorText = ""
    statusText = ""
    flow = "gateway"
    popup.open = true
    focusGatewayInput()
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
    connectProcess.command = ["gp-vpn-connect", gateway, username]
    connectProcess.running = true
  }

  function connectionSucceeded() {
    connected = true
    busy = false
    flow = "connected"
    statusText = "Connected to " + gateway
    saveCredentials.command = ["gp-vpn-credentials", "save", gateway, username]
    saveCredentials.secret = pendingPassword
    saveCredentials.running = true
  }

  function connectionFailed(message) {
    busy = false
    flow = "credentials"
    errorText = message || "Username or password was rejected."
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: statusProcess.running = true
  }

  Process {
    id: statusProcess
    command: ["gp-vpn-status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.connected = String(text || "").trim() === "connected"
    }
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
        root.password = String(text || "").replace(/\n$/, "")
        passwordInput.text = root.password
      }
    }
  }

  Process {
    id: connectProcess
    stdinEnabled: true
    onStarted: {
      write(root.password + "\n")
      root.password = ""
    }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(code) {
      if (code === 0) root.connectionSucceeded()
      else root.connectionFailed("Username or password was rejected, or the VPN connection failed.")
    }
  }

  Process {
    id: saveCredentials
    property string secret: ""
    stdinEnabled: true
    onStarted: {
      write(secret + "\n")
      secret = ""
    }
  }

  Process {
    id: disconnectProcess
    command: ["gp-vpn-disconnect"]
    onExited: {
      root.connected = false
      root.closeFlow()
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
    tooltipText: root.connected ? "GlobalProtect: connected (click to disconnect)" : "GlobalProtect: click to connect"
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
    implicitHeight: Style.space(flow === "gateway" ? 210 : 270)

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
      }

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

        Rectangle {
          width: Style.space(120)
          height: Style.space(32)
          radius: Style.cornerRadius
          color: Color.accent
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
            text: "Cancel"
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
