// NixOS logo centred on a dark background with a password prompt below it,
// laid out like the boot splash (modules/desktop/plymouth). Logs in as the
// last user (or config.user) into the last session; there is no picker.
import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: root
    color: "#121217"

    readonly property string user: userModel.lastUser !== "" ? userModel.lastUser : config.user
    readonly property real unit: height / 48

    Connections {
        target: sddm
        function onLoginFailed() {
            password.text = ""
            password.enabled = true
            message.text = "Wrong password"
            password.forceActiveFocus()
        }
    }

    function login() {
        if (password.text === "")
            return
        message.text = ""
        password.enabled = false
        sddm.login(root.user, password.text, sessionModel.lastIndex)
    }

    Image {
        id: logo
        source: "logo.png"
        width: Math.round(root.height / 4)
        height: width
        sourceSize.width: width
        sourceSize.height: height
        smooth: true
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height / 2 - height / 2 - root.height / 16
    }

    TextField {
        id: password
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: logo.bottom
        anchors.topMargin: root.height / 24
        width: Math.round(logo.width * 1.4)
        height: Math.round(root.unit * 2.2)
        echoMode: TextInput.Password
        passwordCharacter: "•"
        horizontalAlignment: TextInput.AlignHCenter
        placeholderText: "Password"
        placeholderTextColor: "#6c6f7e"
        color: "#e0e0e6"
        font.family: config.font
        font.pixelSize: Math.round(root.unit * 0.8)
        background: Rectangle {
            color: "#2a2d36"
            radius: height / 2
            border.width: password.activeFocus ? 2 : 0
            border.color: "#7ebae4"
        }
        onAccepted: root.login()
        Keys.onEscapePressed: text = ""
    }

    Text {
        id: message
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: password.bottom
        anchors.topMargin: root.unit
        color: "#e78284"
        font.family: config.font
        font.pixelSize: Math.round(root.unit * 0.7)
    }

    Component.onCompleted: password.forceActiveFocus()
}
