import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: root
    color: "#0F0F1A"

    property int sessionIndex: 0
    property color accent: "#3388FF"
    property color textMain: "#FFFFFF"
    property color textDim: "#8899AA"
    property color surface: "#1A1A2E"

    // Background gradient
    gradient: Gradient {
        GradientStop { position: 0.0; color: "#0A0A14" }
        GradientStop { position: 1.0; color: "#0F0F1A" }
    }

    // Accent line top
    Rectangle {
        anchors.top: parent.top
        width: parent.width
        height: 3
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.3; color: root.accent }
            GradientStop { position: 0.7; color: root.accent }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 0

        // Logo / wordmark
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "MorrowOS"
            color: root.textMain
            font.pixelSize: 48
            font.weight: Font.Bold
            font.family: "Sans"
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "Built for Tomorrow"
            color: root.textDim
            font.pixelSize: 14
            font.family: "Sans"
            Layout.topMargin: 6
            Layout.bottomMargin: 48
        }

        // Login card
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: 360
            height: loginCol.implicitHeight + 48
            radius: 12
            color: root.surface
            border.color: "#FFFFFF18"
            border.width: 1

            ColumnLayout {
                id: loginCol
                anchors { left: parent.left; right: parent.right; top: parent.top }
                anchors.margins: 24
                anchors.topMargin: 24
                spacing: 14

                // Username field
                Rectangle {
                    Layout.fillWidth: true
                    height: 44
                    radius: 8
                    color: "#FFFFFF0C"
                    border.color: userField.activeFocus ? root.accent : "#FFFFFF18"
                    border.width: 1

                    TextInput {
                        id: userField
                        anchors { fill: parent; margins: 14 }
                        color: root.textMain
                        font.pixelSize: 14
                        text: sddm.lastUser
                        verticalAlignment: TextInput.AlignVCenter
                        KeyNavigation.tab: passField
                        Keys.onReturnPressed: passField.forceActiveFocus()
                    }
                    Text {
                        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                        text: "Username"
                        color: root.textDim
                        font.pixelSize: 14
                        visible: userField.text.length === 0
                    }
                }

                // Password field
                Rectangle {
                    Layout.fillWidth: true
                    height: 44
                    radius: 8
                    color: "#FFFFFF0C"
                    border.color: passField.activeFocus ? root.accent : "#FFFFFF18"
                    border.width: 1

                    TextInput {
                        id: passField
                        anchors { fill: parent; margins: 14 }
                        color: root.textMain
                        font.pixelSize: 14
                        echoMode: TextInput.Password
                        verticalAlignment: TextInput.AlignVCenter
                        KeyNavigation.tab: loginBtn
                        Keys.onReturnPressed: doLogin()
                    }
                    Text {
                        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                        text: "Password"
                        color: root.textDim
                        font.pixelSize: 14
                        visible: passField.text.length === 0
                    }
                }

                // Error text
                Text {
                    id: errorMsg
                    Layout.fillWidth: true
                    color: "#FF5555"
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    visible: text.length > 0
                }

                // Login button
                Rectangle {
                    id: loginBtn
                    Layout.fillWidth: true
                    Layout.bottomMargin: 0
                    height: 44
                    radius: 8
                    color: loginMouse.containsMouse ? Qt.lighter(root.accent, 1.2) : root.accent
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: "Sign In"
                        color: "white"
                        font.pixelSize: 14
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: loginMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: doLogin()
                    }
                }
            }
        }

        // Clock
        Text {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 40
            color: root.textDim
            font.pixelSize: 13
            text: Qt.formatDateTime(new Date(), "dddd, MMMM d  ·  hh:mm")

            Timer {
                interval: 10000; repeat: true; running: true
                onTriggered: parent.text = Qt.formatDateTime(new Date(), "dddd, MMMM d  ·  hh:mm")
            }
        }
    }

    function doLogin() {
        errorMsg.text = ""
        sddm.login(userField.text, passField.text, sessionIndex)
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            errorMsg.text = "Incorrect username or password"
            passField.text = ""
            passField.forceActiveFocus()
        }
    }

    Component.onCompleted: passField.forceActiveFocus()
}
