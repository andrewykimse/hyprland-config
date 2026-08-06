pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.UPower
import "Singletons"

/**
 * Battery surface: charge readout over a row of power-profile tiles (Power
 * Saver / Balanced / Performance), mirroring Power.qml's session-tile layout
 * but toggling persistent state instead of firing once. The active profile
 * tile stays lit; others light only on hover.
 */
PillSurface {
    id: root

    mTop: 15
    mLeft: 17
    mRight: 17
    mBottom: 14

    property string hovered: ""

    readonly property var device: UPower.displayDevice
    readonly property int pct: Math.round(device.percentage * 100)
    readonly property bool charging: device.state === UPowerDeviceState.Charging
    readonly property bool fullyCharged: device.state === UPowerDeviceState.FullyCharged
    readonly property real etaSeconds: charging ? device.timeToFull : device.timeToEmpty
    readonly property string etaText: {
        if (fullyCharged) return "Fully charged";
        if (etaSeconds <= 0) return "";
        const mins = Math.round(etaSeconds / 60);
        const h = Math.floor(mins / 60);
        const m = mins % 60;
        const label = charging ? "until full" : "remaining";
        return (h > 0 ? h + "h " + m + "m " : m + "m ") + label;
    }

    readonly property var profiles: [
        { key: PowerProfile.PowerSaver,  glyph: "leaf",  label: "Power Saver" },
        { key: PowerProfile.Balanced,    glyph: "scale", label: "Balanced" },
        { key: PowerProfile.Performance, glyph: "bolt",  label: "Performance" }
    ]

    function setProfile(key) {
        PowerProfiles.profile = key;
    }

    onActiveChanged: if (!active) hovered = ""

    Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 34 * root.s

        Row {
            anchors.left: parent.left
            anchors.top: parent.top
            spacing: 8 * root.s
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "電"
                color: Theme.cream
                font.family: Theme.fontJp
                font.weight: Font.Medium
                font.pixelSize: 16 * root.s
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "BATTERY"
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 10 * root.s
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.6 * root.s
            }
        }

        Row {
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: 6 * root.s

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.pct + "%"
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 13 * root.s
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
            }
        }

        Text {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.topMargin: 18 * root.s
            visible: text.length > 0
            text: root.etaText
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 9.5 * root.s
            font.weight: Font.Medium
        }
    }

    Row {
        id: tiles
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: header.bottom
        anchors.topMargin: 14 * root.s
        spacing: 12 * root.s

        Repeater {
            model: root.profiles

            delegate: Item {
                id: tile
                required property var modelData
                readonly property bool isActive: PowerProfiles.profile === modelData.key
                readonly property bool isHover: root.hovered === modelData.label
                readonly property bool lit: isActive || isHover
                width: 50 * root.s
                height: 50 * root.s

                Rectangle {
                    anchors.fill: parent
                    radius: Motion.rTile * root.s
                    color: tile.isActive ? Theme.frameBg : (tile.isHover ? Theme.frameBg : "transparent")
                    border.width: 1
                    border.color: tile.isActive ? Theme.vermLit : (tile.isHover ? Theme.frameBorder : Theme.border)
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                    Behavior on border.color { ColorAnimation { duration: Motion.fast } }
                }

                GlyphIcon {
                    anchors.centerIn: parent
                    width: 22 * root.s
                    height: 22 * root.s
                    name: tile.modelData.glyph
                    color: tile.lit ? Theme.cream : Theme.iconDim
                    stroke: 1.9
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.hovered = tile.modelData.label
                    onExited: if (root.hovered === tile.modelData.label) root.hovered = ""
                    onClicked: root.setProfile(tile.modelData.key)
                }
            }
        }
    }

    Text {
        id: label
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: tiles.bottom
        anchors.topMargin: 12 * root.s
        readonly property var focusProfile: {
            for (var i = 0; i < root.profiles.length; i++)
                if (root.profiles[i].label === root.hovered)
                    return root.profiles[i];
            return null;
        }
        text: focusProfile ? focusProfile.label : ""
        color: Theme.subtle
        font.family: Theme.font
        font.pixelSize: 11 * root.s
        font.weight: Font.Medium
        font.letterSpacing: 0.4 * root.s
        opacity: text.length > 0 ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }
}
