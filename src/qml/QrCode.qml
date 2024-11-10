// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2024 Droidian Project
// Copyright (C) 2024 Furi Labs
//
// Authors:
// Joaquin Philco <joaquinphilco@gmail.com>

import ZXing 1.0
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtGraphicalEffects 1.0
import QtMultimedia 5.15
import QtQuick.Shapes 1.12
import QtQuick.Layouts 1.15


Item {
    id: barcodeReaderComponent

    property alias qrcode : barcodeReader
    property Item viewfinder

    property var lastValidResult: null
    property var smoothedPosition: QtObject {
        property var topLeft: Qt.point(0, 0)
        property var topRight: Qt.point(0, 0)
        property var bottomLeft: Qt.point(0, 0)
        property var bottomRight: Qt.point(0, 0)
    }
    property var codeObb: QtObject {
        property var topLeft: Qt.point(0, 0)
        property var topRight: Qt.point(0, 0)
        property var bottomLeft: Qt.point(0, 0)
        property var bottomRight: Qt.point(0, 0)
    }

    // TODO: this unit is in image-space, not screen-space
    property double padding: 64
    property double imgPadding: 10

    property double currentOpacity: 0
    property var openPopupFunction: function(title, body, buttons, userdata) {}

    function lowPassFilter(current, previous) {
        if (!previous || previous.x == 0) return current

        var alpha = 0.5
        return Qt.point(alpha * current.x + (1 - alpha) * previous.x,
                        alpha * current.y + (1 - alpha) * previous.y)
    }

    function updateLowPass(current)
    {
        var points = ["topLeft", "topRight", "bottomLeft", "bottomRight"]

        for (var i = 0; i < points.length; i++) {
            smoothedPosition[points[i]] = lowPassFilter(current[points[i]], smoothedPosition[points[i]])
        }
    }

    function updateOBB(position)
    {
        // topLeft is the top left corner of the QR code **in image space**. That means that the top left corner
        // can actually have x/y values that are HIGHER than the bottom right corner's (just as an example).
        // So we need to calculate the center, rotation, and width and create a square from scratch. Normally, this
        // wouldn't be a massive deal, but unfortunately for us, I flunked math. Woooo

        var minX = Math.min(position.topLeft.x, position.topRight.x, position.bottomLeft.x, position.bottomRight.x)
        var maxX = Math.max(position.topLeft.x, position.topRight.x, position.bottomLeft.x, position.bottomRight.x)
        var minY = Math.min(position.topLeft.y, position.topRight.y, position.bottomLeft.y, position.bottomRight.y)
        var maxY = Math.max(position.topLeft.y, position.topRight.y, position.bottomLeft.y, position.bottomRight.y)

        var cx = (minX + maxX) / 2
        var cy = (minY + maxY) / 2

        var rotation = Math.atan2(position.topRight.y - position.topLeft.y,
                                  position.topRight.x - position.topLeft.x)

        var sin = Math.sin(rotation)
        var cos = Math.cos(rotation)

        var size = Math.max(maxX - minX, maxY - minY) * Math.max(Math.abs(sin), Math.abs(cos))

        var halfWidth = size / 2

        halfWidth += padding
        halfWidth *= currentOpacity

        codeObb.topLeft     = viewfinder.mapPointToItem(
                                Qt.point(cx + halfWidth * cos - halfWidth * sin,
                                         cy + halfWidth * sin + halfWidth * cos)
                              )
        codeObb.topRight    = viewfinder.mapPointToItem(
                                Qt.point(cx - halfWidth * cos - halfWidth * sin,
                                         cy - halfWidth * sin + halfWidth * cos)
                              )
        codeObb.bottomLeft  = viewfinder.mapPointToItem(
                                Qt.point(cx + halfWidth * cos + halfWidth * sin,
                                         cy + halfWidth * sin - halfWidth * cos)
                              )
        codeObb.bottomRight = viewfinder.mapPointToItem(
                                Qt.point(cx - halfWidth * cos + halfWidth * sin,
                                         cy - halfWidth * sin - halfWidth * cos)
                              )
    }

    function updateOBBFromImage(position, imgScale, imageX, imageY) {
        codeObb.topLeft = Qt.point(position.topLeft.x + imageX - imgPadding, position.topLeft.y + imageY - imgPadding)
        codeObb.topRight = Qt.point(position.topRight.x + imageX + imgPadding, position.topRight.y + imageY - imgPadding)
        codeObb.bottomLeft = Qt.point(position.bottomLeft.x + imageX - imgPadding, position.bottomLeft.y + imageY + imgPadding)
        codeObb.bottomRight = Qt.point(position.bottomRight.x + imageX + imgPadding, position.bottomRight.y + imageY + imgPadding)

        fadeOut.stop()
        fadeIn.start()
    }

    BarcodeReader {
        id: barcodeReader

        formats: ZXing.QRCode

        tryRotate: false
        tryHarder: false
        tryDownscale: true

        onNewResult: {
            if (result.isValid) {
                if (fadeOut.running || !lastValidResult) {
                    fadeOut.stop()
                    fadeIn.start()
                }

                if (!lastValidResult) {
                    smoothedPosition = {
                        topLeft: result.position.topLeft,
                        topRight: result.position.topRight,
                        bottomLeft: result.position.bottomLeft,
                        bottomRight: result.position.bottomRight
                    }
                }

                lastValidResult = result
            } else if (lastValidResult && !fadeOut.running) {
                fadeIn.stop()
                fadeOut.start()
            }
        }
    }

    function calcButtonX() {
        if (!codeObb) return 0
        return Math.min(codeObb.topLeft.x, codeObb.topRight.x, codeObb.bottomLeft.x, codeObb.bottomRight.x)
    }

    function calcButtonY() {
        if (!codeObb) return 0
        return Math.min(codeObb.topLeft.y, codeObb.topRight.y, codeObb.bottomLeft.y, codeObb.bottomRight.y)
    }

    function calcButtonWidth() {
        if (!codeObb) return 0
        return Math.max(codeObb.topLeft.x, codeObb.topRight.x, codeObb.bottomLeft.x, codeObb.bottomRight.x) - calcButtonX()
    }

    function calcButtonHeight() {
        if (!codeObb) return 0
        return Math.max(codeObb.topLeft.y, codeObb.topRight.y, codeObb.bottomLeft.y, codeObb.bottomRight.y) - calcButtonY()
    }

    Button {
        id: qrOverlay
        visible: lastValidResult != null
        x: calcButtonX()
        y: calcButtonY()
        width: calcButtonWidth()
        height: calcButtonHeight()
        onClicked: {
            // QRCodeHandler.openUrlInFirefox(lastValidResult.text)

            var qrType = QRCodeHandler.parseQrString(lastValidResult.text)

            if (qrType === "URL") {
                openPopupFunction("Open URL?", lastValidResult.text, [
                    {
                        text: "Cancel",
                    },
                    {
                        text: "Copy",
                    },
                    {
                        text: "Open",
                        isPrimary: true,
                    }
                ], lastValidResult.text)
            } else if (qrType === "WIFI") {
                var wifiID =  QRCodeHandler.getWifiId()
                openPopupFunction("Connect to Network?", wifiID, [
                    {
                        text: "Cancel",
                    },
                    {
                        text: "Connect",
                        isPrimary: true,
                    }
                ], wifiID)
            }
        }

        background: Rectangle {
            color: "transparent"
            border.color: "transparent"
        }
    }

    Shape {
        id: polygon
        visible: lastValidResult != null
        opacity: currentOpacity

        ShapePath {
            strokeWidth: 8
            strokeColor: "#3584e4"
            strokeStyle: ShapePath.SolidLine
            capStyle: ShapePath.RoundCap
            fillColor: "transparent"
            startX: codeObb.bottomLeft.x
            startY: codeObb.bottomLeft.y
            PathLine {
                x: codeObb.topLeft.x
                y: codeObb.topLeft.y
            }
            PathLine {
                x: codeObb.topRight.x
                y: codeObb.topRight.y
            }
            PathLine {
                x: codeObb.bottomRight.x
                y: codeObb.bottomRight.y
            }
            PathLine {
                x: codeObb.bottomLeft.x
                y: codeObb.bottomLeft.y
            }
        }
    }

    SequentialAnimation {
        id: paddingAnimation
        running: !!lastValidResult
        loops: Animation.Infinite

        NumberAnimation {
            target: barcodeReaderComponent
            property: "padding"
            from: 32
            to: 86
            duration: 800
            easing.type: Easing.InOutQuad
        }

        NumberAnimation {
            target: barcodeReaderComponent
            property: "padding"
            from: 86
            to: 32
            duration: 800
            easing.type: Easing.InOutQuad
        }
    }

    SequentialAnimation {
        id: imgPaddingAnimation
        running: !!lastValidResult
        loops: Animation.Infinite

        NumberAnimation {
            target: barcodeReaderComponent
            property: "imgPadding"
            from: 12
            to: 36
            duration: 800
            easing.type: Easing.InOutQuad
        }

        NumberAnimation {
            target: barcodeReaderComponent
            property: "imgPadding"
            from: 36
            to: 12
            duration: 800
            easing.type: Easing.InOutQuad
        }
    }

    Timer {
        id: updateLowPassTimer
        interval: 1000 / 120
        running: !!lastValidResult && !!viewfinder
        onTriggered: {
            if (!lastValidResult) return

            barcodeReaderComponent.updateLowPass(lastValidResult.position)
            barcodeReaderComponent.updateOBB(barcodeReaderComponent.smoothedPosition)
            updateLowPassTimer.start()
        }
    }

    SequentialAnimation {
        id: fadeOut
        running: false
        PauseAnimation {
            duration: 500
        }
        NumberAnimation {
            target: barcodeReaderComponent
            property: "currentOpacity"
            to: 0
            duration: 1500
            easing.type: Easing.Bezier
            easing.bezierCurve: [
                0.4, 0,
                0.9, 0,
                1,   1
            ]
        }
        PropertyAction {
            target: barcodeReaderComponent
            property: "lastValidResult"
            value: null
        }
    }

    NumberAnimation {
        id: fadeIn
        running: false
        target: barcodeReaderComponent
        property: "currentOpacity"
        to: 1
        duration: 100
        easing.type: Easing.InOutQuad
    }
}
