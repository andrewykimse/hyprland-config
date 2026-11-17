import QtQuick
import QtMultimedia
import "Singletons"

PillSurface {
    id: root

    mTop: 14
    mLeft: 14
    mRight: 14
    mBottom: 14

    readonly property bool hasCamera: devices.videoInputs.length > 0

    MediaDevices {
        id: devices
    }

    CaptureSession {
        camera: Camera {
            id: cam
            active: root.open && root.hasCamera
            cameraDevice: devices.defaultVideoInput
        }
        videoOutput: video
    }

    Rectangle {
        anchors.fill: parent
        radius: Motion.rTile * root.s
        color: Theme.frameBg
        border.width: 1
        border.color: Theme.border
        clip: true

        VideoOutput {
            id: video
            anchors.fill: parent
            anchors.margins: 1
            fillMode: VideoOutput.PreserveAspectCrop
            transform: Scale {
                origin.x: video.width / 2
                xScale: -1
            }
        }

        Text {
            anchors.centerIn: parent
            visible: !root.hasCamera || cam.error !== Camera.NoError
            text: root.hasCamera ? cam.errorString : "No camera found"
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 11 * root.s
            font.weight: Font.Medium
        }
    }
}
