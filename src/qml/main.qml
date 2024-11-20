// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2023 Droidian Project
// Copyright (C) 2024 Furi Labs
//
// Authors:
// Bardia Moshiri <fakeshell@bardia.tech>
// Erik Inkinen <erik.inkinen@gmail.com>
// Alexander Rutz <alex@familyrutz.com>
// Joaquin Philco <joaquinphilco@gmail.com>

import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Window 2.12
import QtGraphicalEffects 1.0
import QtMultimedia 5.15
import QtQuick.Layouts 1.15
import Qt.labs.settings 1.0
import Qt.labs.platform 1.1
import ZXing 1.0

ApplicationWindow {
    id: window
    width: 400
    height: 800
    visible: true
    title: "CameraWindow"

    Screen.orientationUpdateMask: Qt.PortraitOrientation

    property real refHeight: 1080
    property real refWidth: 2412

    property real scalingRatio: Math.max(Screen.width / refWidth, Screen.height / refHeight)

    property bool videoCaptured: false

    property var countDown: 0
    property var blurView: optionContainer.state == "closed" && infoDrawer.position == 0.0 ? 0 : 1
    property var frontCameras: 0
    property var backCameras: 0
    property var swipeDirection: 0 // 0 = swiped left, 1 = swiped right, 2 = clicked
    property var next_state_left: "Empty"
    property var next_state_right: "VideoCapture"
    property var popupResultHeight: 40
    property var popupState: "closed"
    property var popupTitle: null
    property var popupBody: null
    property var popupData: null
    property var popupButtons: null
    property var mediaViewOpened: false
    property var focusPointVisible: false
    property var cameraAspWide: 1
    property var aeflock: "AEFLockOff"
    property var pinchAreaEnabled: true


    property var gps_icon_source: settings.gpsOn ? "icons/gpsOn.svg" : "icons/gpsOff.svg"
    property var locationAvailable: 0

    signal customClosing()
    signal cameraTakeShot()
    signal cameraTakeVideo()
    signal cameraEnableGestures(bool value)
    signal cameraChangeResolution(string resolution)
    signal stopCamera()
    signal startCamera()
    signal setFlashState(int flashState)
    signal setFocusMode(int focusMode)
    signal setFocusPointMode(int focusPointMode)

    onActiveChanged:{
        // if (camera.cameraState === Camera.UnloadedState && window.active) {
        //     console.log("restarting camera")
        //     //camera.cameraState = Camera.ActiveState
        //    // camera.start()
        // }
    }

    onClosing: {
        console.log("Window closing event triggered")
        close.accepted = false
        console.log("Stopping camera...")
        // camera.stop()
        customClosing()
    }

    function openPopup(title, body, buttons, data) {
        popupTitle = title
        popupBody = body
        popupButtons = buttons
        popupData = data
        popupState = "opened"
    }

    ListModel {
        id: allCamerasModel
        Component.onCompleted: {
            var blacklist

            if (settingsCommon.blacklist != "") {
                blacklist = settingsCommon.blacklist.split(',')
            }

            for (var i = 0; i < QtMultimedia.availableCameras.length; i++) {
                var cameraInfo = QtMultimedia.availableCameras[i];
                var isBlacklisted = false;

                for (var p in blacklist) {
                    if (blacklist[p] == cameraInfo.deviceId) {
                        console.log("Camera with the id:", blacklist[p], "is blacklisted, not adding to camera list!");
                        isBlacklisted = true;
                        break;
                    }
                }

                if (isBlacklisted) {
                    continue;
                }

                if (cameraInfo.position === Camera.BackFace) {
                    append({"cameraId": cameraInfo.deviceId, "index": i, "position": cameraInfo.position});
                    window.backCameras += 1;
                } else if (cameraInfo.position === Camera.FrontFace) {
                    insert(0, {"cameraId": cameraInfo.deviceId, "index": i, "position": cameraInfo.position});
                    window.frontCameras += 1;
                }
            }
        }
    }

    Settings {
        id: settings
        objectName: "settingsObject"
        property int cameraId: 0
        property int aspWide: 0
        property int flashMode: Camera.FlashOff
        property int focusMode: Camera.FocusAuto
        property int focusPointMode: Camera.FocusPointCustom
        property var cameras: [{"cameraId": 0, "resolution": 0},
                                {"cameraId": 1, "resolution": 0},
                                {"cameraId": 2, "resolution": 0},
                                {"cameraId": 3, "resolution": 0},
                                {"cameraId": 4, "resolution": 0},
                                {"cameraId": 5, "resolution": 0},
                                {"cameraId": 6, "resolution": 0},
                                {"cameraId": 7, "resolution": 0},
                                {"cameraId": 8, "resolution": 0},
                                {"cameraId": 9, "resolution": 0}]
        property int soundOn: 1
        property var hideInfoDrawer: 0
        property int gpsOn: 0
        property int cameraPosition: Camera.FrontFace
        property int settingsAspWide: 0
        property var cameraDeviceId: model.cameraId;

        onFocusModeChanged: setFocusMode(settings.focusMode)
        onFocusPointModeChanged: setFocusPointMode(settings.focusPointMode)
    }

    Settings {
        id: settingsCommon
        fileName: fileManager.getConfigFile(); //"/etc/furios-camera.conf" or "/usr/lib/furios/device/furios-camera.conf"

        property var blacklist: 0
    }

    background: Rectangle {
        color: "black"
    }

    Item {
        id: focusState

        state: "AutomaticFocus"

        states: [
            State {
                name: "WaitingForTarget" // AEF lock on and waiting for target.

                PropertyChanges {
                    target: settings
                    focusMode: Camera.FocusContinuous
                    focusPointMode: Camera.FocusPointCustom
                }
            },
            State {
                name: "TargetLocked" // First touch after AEF Lock started.

                PropertyChanges {
                    target: settings
                    focusMode: Camera.FocusContinuous
                    focusPointMode: Camera.FocusPointCustom
                }
            },
            State {
                name: "AutomaticFocus" // Moving around and no touch, no AEF lock.

                PropertyChanges {
                    target: settings
                    focusMode: Camera.FocusAuto
                    focusPointMode: Camera.FocusPointCustom
                }
            }
        ]
    }

    Item {
        id: cslate

        state: "PhotoCapture"

        states: [
            State {
                name: "PhotoCapture"

                PropertyChanges {
                    target: window
                    next_state_left:"Empty" 
                }

                PropertyChanges {
                    target: window
                    next_state_right: "VideoCapture"
                }
            },
            State {
                name: "VideoCapture"

                PropertyChanges {
                    target: window
                    next_state_left: "PhotoCapture"
                }

                PropertyChanges {
                    target: window
                    next_state_right: "Empty"
                }
            }
        ]
    }

    Loader {
        anchors.fill: parent
        id: cameraLoader
        asynchronous: true
        source: "Camera.qml"

        onLoaded: {
            console.log("Camera component has been loaded!")
            window.cameraTakeShot.connect(cameraLoader.item.handleCameraTakeShot);
            window.cameraTakeVideo.connect(cameraLoader.item.handleCameraTakeVideo);
            window.cameraChangeResolution.connect(cameraLoader.item.handleCameraChangeResolution);
            window.stopCamera.connect(cameraLoader.item.handleStopCamera);
            window.setFlashState.connect(cameraLoader.item.handleSetFlashState);
            window.startCamera.connect(cameraLoader.item.handleStartCamera);
            window.setFocusPointMode.connect(cameraLoader.item.handleSetFocusPointMode);
            window.setFocusMode.connect(cameraLoader.item.handleSetFocusMode);
        }
    }

    SoundEffect {
        id: sound
        source: "sounds/camera-shutter.wav"
    }

    // Rectangle {
    //     id: videoFrame
    //     anchors.fill: parent
    //     color: "black"
    // }

    Timer {
        id: swappingDelay
        interval: 400
        repeat: false
        property var next_state: ""

        onTriggered: {
            if (window.swipeDirection != 2){
                swappingDelay.next_state = (swipeDirection == 0) ? window.next_state_left : window.next_state_right;
                cslate.state = next_state === "Empty" ? cslate.state : swappingDelay.next_state;
            }
            window.blurView = 0
        }
    }

    Timer {
        id: cameraSwitchDelay
        interval: 100
        repeat: false

        onTriggered: {
            window.blurView = 0;
        }
    }

    Timer {
        id: aefLockTimer
        interval: 2000
        repeat: false

        onTriggered: {
            if (focusState.state !== "TargetLocked") {
                focusState.state = "AutomaticFocus"
                window.aeflock = "AEFLockOff"
            }
        }
    }

    Rectangle {
        id: optionContainer
        width: parent.width
        height: parent.height * .5
        anchors.verticalCenter: parent.verticalCenter
        state: "closed"

        color: "transparent"

        states: [
            State {
                name: "opened"
                PropertyChanges {
                    target: optionContainer
                    x: window.width / 2 - optionContainer.width / 2
                }
            },

            State {
                name: "closed"
                PropertyChanges {
                    target: optionContainer
                    x: window.width
                }
            }
        ]

        ColumnLayout {
            anchors.fill: parent

            ColumnLayout {
                id: backCamSelect
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: true

                function getSpaces(numDigits) {
                    if (numDigits === 1) {
                        return "      ";
                    } else if (numDigits === 2) {
                        return "    ";
                    } else if (numDigits === 3) {
                        return " ";
                    } else {
                        return "";
                    }
                }

                Repeater {
                    model: allCamerasModel
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: parent.width * 0.9
                    Button {
                        property var pos: model.position == 1 ? "Back" : "Front"
                        property var numDigits: settings.cameras[model.cameraId].resolution.toString().length
                        Layout.alignment: Qt.AlignLeft
                        visible: parent.visible
                        icon.source: "icons/cameraVideoSymbolic.svg"
                        icon.color: "white"
                        icon.width: 48
                        icon.height: 48
                        palette.buttonText: "white"

                        font.pixelSize: 32
                        font.bold: true
                        text: " " + settings.cameras[model.cameraId].resolution + "MP" + backCamSelect.getSpaces(numDigits) + pos

                        background: Rectangle {
                            anchors.fill: parent
                            color: "transparent"
                        }

                        onClicked: {
                            window.blurView = 0
                            //camera.deviceId = model.cameraId
                            settings.cameraDeviceId = model.cameraId
                            optionContainer.state = "closed"
                        }
                    }
                }
            }
        }

        Behavior on x {
            PropertyAnimation {
                duration: 300
            }
        }
    }

    Timer {
        id: preCaptureTimer
        interval: 1000
        onTriggered: {
            countDown -= 1
            if (countDown < 1) {
                window.cameraTakeShot()
                preCaptureTimer.stop();
            }
        }

        running: false
        repeat: true
    }

    Drawer {
        id: infoDrawer
        width: parent.width
        edge: Qt.BottomEdge
        dim: true
        interactive: settings.hideInfoDrawer != 1

        background: Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: 0.9
        }

        GridLayout {
            columnSpacing: 5
            rowSpacing: 25
            anchors.centerIn: parent
            width: parent.width * 0.9
            columns: 2
            rows: 2

            Button {
                icon.source: "icons/helpAboutSymbolic.svg"
                icon.color: "lightblue"
                icon.width: 48
                icon.height: 48
                Layout.preferredWidth: icon.width * 1.5
                Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
                Layout.topMargin: 10

                background: Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                }
            }

            Text {
                Layout.alignment: Qt.AlignLeft
                Layout.fillWidth: true
                Layout.topMargin: 10
                text: "Swipe down for more options"
                horizontalAlignment: Text.AlignHCenter
                color: "white"
                font.pixelSize: 32
                font.bold: true
                style: Text.Outline;
                styleColor: "black"
                wrapMode: Text.WordWrap
            }

            Button {
                icon.source: "icons/emblemDefaultSymbolic.svg"
                icon.color: "white"
                icon.width: 48
                icon.height: 48
                Layout.columnSpan: 2
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true

                background: Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                }

                onClicked: {
                    infoDrawer.close()
                    settings.hideInfoDrawer = 1
                    settings.setValue("hideInfoDrawer", 1);
                }
            }
        }
        onClosed: {
            window.blurView = 0;
        }
    }

    Item {
        id: mainBar
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 43 * window.scalingRatio
        height: 150 * window.scalingRatio
        width: parent.width
        visible: !mediaView.visible

        Item {
            id: hotBar
            anchors.top: parent.top
            anchors.horizontalCenter: mainBar.horizontalCenter
            width: parent.width
            height: parent.height / 3
            visible: !window.videoCaptured

            Rectangle {
                id: flashButtonFrame
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                width: parent.width * 0.15
                radius: 20
                color: "transparent"
                anchors.leftMargin: 40 * window.scalingRatio

                Button {
                    id: flashButton

                    height: width
                    anchors.fill: parent
                    
                    icon.height: parent.height / 1.5
                    icon.width: parent.height / 1.5
                    icon.color: "white"
                    icon.source: {
                        switch(settings.flashMode) {
                            case Camera.FlashOff: return "icons/flashOff.svg";
                            case Camera.FlashOn: return "icons/flashOn.svg";
                            case Camera.FlashAuto: return "icons/flashAuto.svg";
                            default: return "icons/flashOff.svg";
                        }
                    }

                    background: Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                    }

                    onClicked: {
                        console.log("flash button");
                        if (settings.cameraPosition !== Camera.FrontFace) {
                            console.log("enabled")
                            switch(settings.flashMode) {
                                case Camera.FlashOff:
                                    settings.flashMode = Camera.FlashOn;
                                    break;
                                case Camera.FlashOn:
                                    settings.flashMode = Camera.FlashAuto;
                                    break;
                                case Camera.FlashAuto:
                                    settings.flashMode = Camera.FlashOff;
                                    break;
                            }
                            window.setFlashState(settings.flashMode);
                        }
                    }
                }
            }

            Rectangle {
                id: changeStateBtnFrame
                width: hotBar.width * 0.4
                height: hotBar.height * 0.9
                color: "transparent"
                anchors.centerIn: parent

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Item {
                        width: changeStateBtnFrame.width
                        height: changeStateBtnFrame.height
                        Rectangle {
                            anchors.fill: parent
                            radius: 30 * window.scalingRatio
                        }
                    }
                }

                Rectangle {
                    anchors.fill: changeStateBtnFrame
                    color: "#ff383838"
                    anchors.centerIn: parent

                    RowLayout {
                        width: parent.width
                        height: parent.height
                        spacing: 0

                        Button {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            icon.source: "icons/cameraState.svg"
                            icon.height: parent.height * 0.5
                            icon.width: parent.height * 0.5 * 1.067
                            icon.color: "white"

                            background: Rectangle {
                                color: cslate.state === "PhotoCapture" ? "transparent" : "#33ffffff"

                                Behavior on color {
                                    ColorAnimation {
                                        duration: 300
                                    }
                                }
                            }

                            onClicked: {
                                if (cslate.state != "PhotoCapture") {
                                    optionContainer.state = "closed"
                                    cslate.state = "PhotoCapture"
                                    window.swipeDirection = 2
                                    window.blurView = 1
                                    swappingDelay.start()
                                }
                            }
                        }

                        Button {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            icon.source: "icons/videoState.svg"
                            icon.height: parent.height * 0.5
                            icon.width: parent.height * 0.5
                            icon.color: "white"

                            background: Rectangle {
                                color: cslate.state === "VideoCapture" ? "transparent" : "#33ffffff"

                                Behavior on color {
                                    ColorAnimation {
                                        duration: 300
                                    }
                                }
                            }

                            onClicked: {
                                if (cslate.state != "VideoCapture") {
                                    optionContainer.state = "closed"
                                    cslate.state = "VideoCapture"
                                    window.swipeDirection = 2
                                    window.blurView = 1
                                    swappingDelay.start()
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: aefLockBtnFrame
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height + 10
                width: parent.width * 0.15
                radius: 20 * window.scalingRatio
                color: "transparent"
                anchors.rightMargin: 43 * window.scalingRatio

                Button {
                    id: aefLockBtn

                    height: width
                    anchors.fill: parent
                    icon.source: window.aeflock === "AEFLockOn" ? "icons/AEFLockOn.svg" : "icons/AEFLockOff.svg"
                    icon.height: parent.height / 1.5
                    icon.width: parent.height / 1.5
                    icon.color: "white"

                    background: Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                    }

                    onClicked: {
                        if (settings.cameraPosition !== Camera.FrontFace) {
                            if (window.aeflock === "AEFLockOff") {
                                focusState.state = "WaitingForTarget";
                                window.aeflock = "AEFLockOn";
                                aefLockTimer.start();
                            } else {
                                window.aeflock = "AEFLockOff";
                                focusState.state = "AutomaticFocus";
                                window.focusPointVisible = false;
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: aefLockLabel
                anchors.horizontalCenter: hotBar.horizontalCenter
                anchors.bottom: parent.top
                width: hotBar.width * 0.4
                height: hotBar.height * 0.8
                radius: 15 * window.scalingRatio
                color: "#FDD017"

                visible: window.aeflock === "AEFLockOn" || focusState.state === "TargetLocked"

                Text {
                    text: focusState.state === "WaitingForTarget" ? "Select a Target" : "AE/AF Lock On"
                    color: "black"
                    font.pixelSize: 17 * window.scalingRatio
                    style: Text.Raised
                    styleColor: "black"
                    elide: Text.ElideRight
                    anchors.centerIn: parent
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: 300
                        easing.type: Easing.InOutQuad
                    }
                }

                onVisibleChanged: {
                    opacity = visible ? 1 : 0
                }
            }
        }

        Item {
            id: mainBarBottom
            anchors.bottom: mainBar.bottom
            width: parent.width
            height: parent.height - hotBar.height

            Rectangle {
                id: rotateBtnFrame
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height * 0.65
                width: height
                radius: width / 2
                color: "#333333"
                anchors.rightMargin: 45 * window.scalingRatio
                visible: !window.videoCaptured

                Button {
                    id: rotateCamera
                    anchors.fill: parent
                    icon.source: "icons/rotateCamera.svg"
                    icon.color: "white"
                    icon.width: rotateBtnFrame.height * 0.45
                    icon.height: rotateBtnFrame.height * 0.3
                    enabled: !window.videoCaptured
                    visible: optionContainer.state == "closed"

                    background: Rectangle {
                        color: "transparent"
                    }

                    onClicked: {
                        if (settings.cameraPosition === Camera.BackFace) {
                            flashButton.state = "flashOff"
                            settings.cameraPosition = Camera.FrontFace;
                        } else if (settings.cameraPosition === Camera.FrontFace) {
                            settings.cameraPosition = Camera.BackFace;
                        }
                    }
                }
            }

            Rectangle {
                id: reviewBtnFrame
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height * 0.65
                width: height
                radius: width / 2
                anchors.leftMargin: 45 * window.scalingRatio
                enabled: !window.videoCaptured
                visible: !window.videoCaptured

                Rectangle {
                    id: reviewBtn
                    anchors.fill: parent
                    color: "black"
                    layer.enabled: true

                    layer.effect: OpacityMask {
                        maskSource: Item {
                            width: reviewBtn.width
                            height: reviewBtn.height

                            Rectangle {
                                anchors.centerIn: parent
                                width: reviewBtn.adapt ? reviewBtn.width : Math.min(reviewBtn.width, reviewBtn.height)
                                height: reviewBtn.adapt ? reviewBtn.height : width
                                radius: width / 2
                            }
                        }
                    }

                    Image {
                        anchors.centerIn: parent
                        autoTransform: true
                        transformOrigin: Item.Center
                        fillMode: Image.Stretch
                        smooth: false
                        source: (cslate.state == "PhotoCapture") ? mediaView.lastImg : ""
                        scale: Math.min(parent.width / width, parent.height / height)
                    }
                }

                Rectangle {
                    anchors.fill: reviewBtn
                    color: "transparent"
                    radius: 5 * window.scalingRatio

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            mediaView.visible = true;
                        }
                    }
                }
            }

            Loader {
                id: stateBtnLoader
                anchors.fill: parent
                asynchronous: true
                sourceComponent: cslate.state === "PhotoCapture"? shutterBtnComponent : videoBtnComponent
            }

            Component {
                id: shutterBtnComponent
                Item {
                    Rectangle {
                        id: shutterBtnFrame
                        height: parent.height * 0.75
                        width: height
                        radius: 75 * window.scalingRatio
                        color: "white"
                        anchors.centerIn: parent
                        visible: cslate.state === "PhotoCapture"

                        Loader {
                            id: shutterBtnLoader
                            anchors.fill: parent
                            asynchronous: true
                            sourceComponent: configBar.opened === 1 || preCaptureTimer.running ? timerShutter : pictureShutter
                        }

                        Component{
                            id: pictureShutter
                            Item {
                                Rectangle {
                                    anchors.centerIn: parent
                                    height: shutterBtnFrame.height * 0.8
                                    width: height
                                    radius: 55 * window.scalingRatio
                                    color: "black"
                                }

                                Button {
                                    id: shutterBtn
                                    anchors.centerIn: parent
                                    height: shutterBtnFrame.height
                                    width: height
                                    enabled: cslate.state === "PhotoCapture" && !mediaView.visible

                                    background: Rectangle {
                                        id: camerabtn
                                        anchors.centerIn: parent
                                        height: shutterBtnFrame.height * 0.74
                                        width: height
                                        radius: 55 * window.scalingRatio
                                        color: "white"

                                        SequentialAnimation on color {
                                            id: animation
                                            running: false

                                            ColorAnimation {
                                                target: camerabtn
                                                property: "color"
                                                from: "white"
                                                to: "gray"
                                                duration: 150
                                            }

                                            ColorAnimation {
                                                target: camerabtn
                                                property: "color"
                                                from: "gray"
                                                to: "white"
                                                duration: 150
                                            }
                                        }
                                    }

                                    onClicked: {
                                        animation.start();                            
                                        window.blurView = 0
                                        window.cameraTakeShot()
                                    }
                                }
                            }
                        }

                        Component {
                            id: timerShutter
                            Item {
                                Button {
                                    id: shutterBtn
                                    anchors.fill: parent.fill
                                    anchors.centerIn: parent
                                    enabled: cslate.state === "PhotoCapture" && !mediaView.visible
                                    icon.source: preCaptureTimer.running ? "" : configBar.currIndex === 0 ? "icons/windowCloseSymbolic.svg" : "icons/timer.svg"
                                    icon.color: "white"
                                    icon.width: shutterBtnFrame.width - 10
                                    icon.height: shutterBtnFrame.height - 10

                                    text: preCaptureTimer.running ? countDown : ""

                                    palette.buttonText: "red"

                                    font.pixelSize: 50
                                    font.bold: true
                                    font.family: "Lato Hairline"
                                    visible: true

                                    background: Rectangle {
                                        anchors.centerIn: parent
                                        width: shutterBtnFrame.width
                                        height: shutterBtnFrame.height
                                        color: "black"
                                        radius: shutterBtnFrame.radius - 10
                                    }

                                    onClicked: {
                                        //window.pinchAreaEnabled = true
                                        //pinchArea.enabled = true
                                        window.blurView = 0

                                        if (configBar.currIndex > 0) {
                                            configBar.opened = 0
                                            optionContainer.state = "closed"
                                            countDown = configBar.currIndex
                                            preCaptureTimer.start()
                                        } else if (configBar.currIndex < 1) {
                                            optionContainer.state = "closed"
                                            configBar.opened = 0
                                        }
                                    }
                                }
                            }

                        }
                    }
                }
            }

            Component {
                id: videoBtnComponent
                Item {
                    Rectangle {
                        id: videoBtnFrame
                        height: parent.height * 0.75
                        width: height
                        radius: 70 * window.scalingRatio
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        visible: cslate.state === "VideoCapture"

                        Button {
                            id: videoBtn
                            anchors.fill: parent
                            enabled: !mediaView.visible

                            Rectangle {
                                id: redCircle
                                anchors.centerIn: parent
                                height: videoBtnFrame.height * 0.5
                                width: height
                                color: "red"
                                radius: videoBtnFrame.radius
                                visible: true

                                ParallelAnimation {
                                    id: redCircleAnimation

                                    PropertyAnimation {
                                        target: redCircle
                                        property: "opacity"
                                        from: !window.videoCaptured ? 1.0 : 0
                                        to: window.videoCaptured ? 1.0 : 0
                                        duration: 400
                                    }

                                    PropertyAnimation {
                                        target: redCircle
                                        property: "width"
                                        from: !window.videoCaptured ? videoBtnFrame.height * 0.5 : 0
                                        to: window.videoCaptured ? videoBtnFrame.height * 0.5 : 0
                                        duration: 400
                                    }

                                    PropertyAnimation {
                                        target: redCircle
                                        property: "height"
                                        from: !window.videoCaptured ? videoBtnFrame.height * 0.5 : 0
                                        to: window.videoCaptured ? videoBtnFrame.height * 0.5 : 0
                                        duration: 400
                                    }

                                    onStopped: {
                                        redCircle.visible = !window.videoCaptured
                                    }
                                }
                            }

                            Rectangle {
                                id: blackSquare
                                anchors.centerIn: parent
                                visible: false
                                height: videoBtnFrame.height * 0.5
                                width: height
                                radius: 6 * window.scalingRatio
                                color: "black"

                                ParallelAnimation {
                                    id: blackSquareAnimation

                                    PropertyAnimation {
                                        target: blackSquare
                                        property: "opacity"
                                        from: window.videoCaptured ? 1.0 : 0
                                        to: !window.videoCaptured ? 1.0 : 0
                                        duration: 400
                                    }

                                    PropertyAnimation {
                                        target: blackSquare
                                        property: "width"
                                        from: window.videoCaptured ? videoBtnFrame.height * 0.5 : 0
                                        to: !window.videoCaptured ? videoBtnFrame.height * 0.5 : 0
                                        duration: 400
                                    }

                                    PropertyAnimation {
                                        target: blackSquare
                                        property: "height"
                                        from: window.videoCaptured ? videoBtnFrame.height * 0.5 : 0
                                        to: !window.videoCaptured ? videoBtnFrame.height * 0.5 : 0
                                        duration: 400
                                    }

                                    onStopped: {
                                        blackSquare.visible = window.videoCaptured
                                    }
                                }
                            }

                            text: preCaptureTimer.running ? countDown : ""
                            palette.buttonText: "white"
                            font.pixelSize: 64
                            font.bold: true

                            background: Rectangle {
                                anchors.centerIn: parent
                                width: videoBtnFrame.width
                                height: videoBtnFrame.height
                                color: "white"
                                radius: videoBtnFrame.radius
                            }

                            onClicked: {
                                blackSquareAnimation.start()
                                redCircleAnimation.start()
                                window.cameraTakeVideo()
                            }

                            Behavior on rotation {
                                RotationAnimation {
                                    duration: 250
                                    direction: RotationAnimation.Counterclockwise
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    MediaReview {
        id: mediaView
        anchors.fill: parent
        onClosed: window.startCamera()
        focus: visible

        scalingRatio: window.scalingRatio
    }
    
    Rectangle {
        id: popupBackdrop
        width: window.width
        height: window.height
        color: "#66000000"
        opacity: popupState === "opened" ? 1 : 0
        visible: popupState === "opened"

        Behavior on opacity {
            NumberAnimation {
                duration: 125
            }
        }

        Behavior on visible {
            PropertyAnimation {
                duration: 125
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                popupState = "closed"
            }
        }

        TextEdit {
            id: copyToClipboardHelper
            opacity: 0
            text: popupData
        }

        Rectangle {
            id: popup
            width: window.width * 0.8
            height: window.popupResultHeight + titlePopUp.implicitHeight + popupButtonsRow.height
            color: "#ff383838"
            radius: 10
            anchors.centerIn: parent

            /* adwaita-like popup: big title, center-aligned text, buttons at the bottom */
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                spacing: 0

                Text {
                    id: titlePopUp
                    text: popupTitle
                    color: "white"
                    font.pixelSize: 24
                    font.weight: Font.ExtraBold
                    horizontalAlignment: Text.AlignHCenter
                    width: parent.width
                    wrapMode: Text.WordWrap
                    topPadding: 20
                }

                Loader {
                    id: popupBodyLoader
                    width: parent.width
                    height: window.popupResultHeight
                    asynchronous: true
                    sourceComponent: popupTitle === "Connect to Network?" ? wifiComponent : qrTextComponent
                }

                Component {
                    id: wifiComponent
                    Item {
                        id: wifiItem

                        property var currentSignalIcon: "icons/network-wireless-signal-offline.svg"
                        property var isFirstPopup: false

                        RowLayout {
                            anchors.horizontalCenter: parent.horizontalCenter

                            Timer {
                                id: signalStrengthIconTimer
                                interval: 3000
                                repeat: true
                                running: wifiItem.visible
                                onTriggered: {
                                    currentSignalIcon = QRCodeHandler.getSignalStrengthIcon()

                                    if (isFirstPopup == false){
                                       isFirstPopup = true;
                                    }
                                }
                            }

                            Text {
                                id: wifiBodyPopUp
                                text: popupBody
                                color: "white"
                                font.pixelSize: 16
                                horizontalAlignment: Text.AlignHCenter
                                Layout.alignment: Qt.AlignVCenter
                                width: parent.width
                                wrapMode: Text.Wrap
                                padding: 10
                                topPadding: 10
                                bottomPadding: 25
                            }

                            Button {
                                id: wifiButton
                                icon.source: isFirstPopup ? currentSignalIcon : QRCodeHandler.getSignalStrengthIcon()
                                icon.color: "white"
                                padding: 10
                                topPadding: 10
                                bottomPadding: 25
                                width: 30 * window.scalingRatio
                                height: 30 * window.scalingRatio
                                flat: true

                                Component.onCompleted: {
                                    window.popupResultHeight = 40
                                }
                            }
                        }
                    }
                }

                Component {
                    id: qrTextComponent
                    Item {
                        id: qrTextItem

                        Text {
                            id: bodyPopUp
                            text: popupBody
                            color: "white"
                            font.pixelSize: 16
                            horizontalAlignment: Text.AlignHCenter
                            Layout.alignment: Qt.AlignVCenter
                            width: parent.width
                            wrapMode: Text.Wrap
                            padding: 10
                            topPadding: 10
                            Component.onCompleted: {
                                window.popupResultHeight = bodyPopUp.implicitHeight
                            }
                            onTextChanged: {
                                window.popupResultHeight = bodyPopUp.implicitHeight
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: popupButtonsRow
                width: parent.width
                height: 48
                color: "transparent"
                anchors.bottom: parent.bottom
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter | Qt.AlignBottom
                    width: parent.width
                    height: parent.height
                    spacing: 0

                    Repeater {
                        model: popupButtons
                        Button {
                            text: modelData.text
                            onClicked: {
                                popupState = "closed"
                                // modelData.onClicked(popupData)

                                // jesus todo: I don't know why but I can't call functions passed inside the object.
                                // printing the keys shows that the function is there, but calling it says it's undefined. ???

                                if (modelData.text === "Open") {
                                    QRCodeHandler.openUrlInFirefox(popupData)
                                } else if (modelData.text === "Connect") {
                                    QRCodeHandler.connectToWifi();
                                } else if (modelData.text === "Copy") {
                                    /* oh god */
                                    copyToClipboardHelper.selectAll()
                                    copyToClipboardHelper.copy()
                                }
                            }

                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            background: Rectangle {
                                color: parent.down ? "#33ffffff" : "transparent"

                                Behavior on color {
                                    ColorAnimation {
                                        duration: 100
                                    }
                                }
                            }

                            palette.buttonText: modelData.isPrimary ? "#62a0ea" : "white"
                            font.pixelSize: 16
                            font.bold: true

                            clip: true
                            Rectangle {
                                visible: popupButtons.length > 1 && index < popupButtons.length - 1 ? 1 : 0
                                border.width: 1
                                border.color: "#565656"
                                anchors.fill: parent
                                anchors.leftMargin: -1
                                anchors.topMargin: -1
                                anchors.bottomMargin: -1
                                color: "transparent"
                            }
                        }
                    }
                }

                /* top border */
                clip: true
                Rectangle {
                    border.width: 1
                    border.color: "#565656"
                    anchors.fill: parent
                    anchors.leftMargin: -2
                    anchors.rightMargin: -2
                    anchors.bottomMargin: -2
                    color: "transparent"
                }
            }
        }
        DropShadow {
            anchors.fill: popup
            horizontalOffset: 0
            verticalOffset: 1
            radius: 8
            samples: 6
            color: "#44000000"
            source: popup
        }
    }

    Drawer {
        id: configBarDrawer
        height: 55 * window.scalingRatio
        width: window.width
        dim: false
        edge: Qt.TopEdge
        modal: false
        interactive: false

        visible: !configBarBtn.visible

        background: Rectangle {
            anchors.fill: parent
            color: "transparent"
        }

        Item {
            id: configBar
            width: parent.width
            height: configBarDrawer.height
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 20 * window.scalingRatio

            property var opened: 0;
            property var aspectRatioOpened: 0;
            property var currIndex: timerTumbler.currentIndex
            visible: !mediaView.visible && !window.videoCaptured

            RowLayout {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: configBarDrawer.height * 0.8

                Button {
                    icon.source: settings.soundOn === 1 ? "icons/audioOn.svg" : "icons/audioOff.svg"
                    icon.height: configBarDrawer.height * 0.6
                    icon.width: configBarDrawer.height * 0.6
                    icon.color: settings.soundOn === 1 ? "white" : "grey"

                    background: Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                    }

                    onClicked: {
                        settings.soundOn = settings.soundOn === 1 ? 0 : 1;
                    }
                }

                Button {
                    icon.source: window.gps_icon_source
                    icon.height: configBarDrawer.height * 0.6
                    icon.width: configBarDrawer.height * 0.6
                    icon.color: window.locationAvailable === 1 ? "white" : "grey"

                    background: Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                    }

                    Connections {
                        target: fileManager

                        function onGpsDataReady() {
                            window.gps_icon_source = "icons/gpsOn.svg";
                            window.locationAvailable = 1;
                        }
                    }

                    onClicked: {
                        settings.gpsOn = settings.gpsOn === 1 ? 0 : 1;

                        if (settings.gpsOn === 1) {
                            fileManager.turnOnGps();
                        } else {
                            fileManager.turnOffGps();
                            window.gps_icon_source = "icons/gpsOff.svg";
                            window.locationAvailable = 0;
                        }
                    }

                    Connections {
                        target: fileManager

                        function onGpsDataReady() {
                            window.gps_icon_source = "icons/gpsOn.svg";
                            window.locationAvailable = 1;
                        }
                    }
                }

                Button {
                    id: timerButton
                    icon.source: "icons/timer.svg"
                    icon.height: configBarDrawer.height * 0.6
                    icon.width: configBarDrawer.height * 0.6
                    icon.color: "white"

                    background: Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                    }

                    onClicked: {
                        configBar.opened = configBar.opened === 1 ? 0 : 1
                        configBar.aspectRatioOpened = 0
                        optionContainer.state = "closed"
                        window.blurView = 1
                    }

                    Tumbler {
                        id: timerTumbler
                        height: 200 * window.scalingRatio
                        width: 50 * window.scalingRatio
                        anchors.horizontalCenter: timerButton.horizontalCenter
                        Layout.preferredWidth: parent.width
                        anchors.top: timerButton.bottom
                        model: 60
                        visible: configBar.opened === 1 ? true : false
                        enabled: configBar.opened === 1 ? true : false

                        delegate: Text {
                            text: modelData == 0 ? "Off" : modelData
                            color: "white"
                            font.bold: true
                            font.pixelSize: 30 * window.scalingRatio
                            font.family: "Lato Hairline"
                            horizontalAlignment: Text.AlignHCenter
                            opacity: 0.4 + Math.max(0, 1 - Math.abs(Tumbler.displacement)) * 0.6
                        }

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 300
                                easing.type: Easing.InOutQuad
                            }
                        }

                        onVisibleChanged: {
                            opacity = visible ? 1 : 0
                        }
                    }
                }

                Button {
                    id: aspectRatioButton
                    icon.source: "icons/aspectRatioMenu.svg"
                    icon.height: configBarDrawer.height * 0.6
                    icon.width: configBarDrawer.height * 0.6
                    icon.color: "white"

                    background: Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                    }

                    onClicked: {
                        configBar.aspectRatioOpened = configBar.aspectRatioOpened === 1 ? 0 : 1
                        optionContainer.state = "closed"
                        configBar.opened = 0
                    }

                    ColumnLayout {
                        id: aspectRatios
                        anchors.top: aspectRatioButton.bottom
                        anchors.horizontalCenter: aspectRatioButton.horizontalCenter
                        visible: configBar.aspectRatioOpened === 1 ? true : false
                        spacing: 5 * window.scalingRatio

                        Button {
                            id: sixteenNineButton
                            text: "16:9"
                            Layout.preferredWidth: 60 * window.scalingRatio
                            font.pixelSize:  35 * window.scalingRatio * 0.5
                            font.bold: true
                            font.family: "Lato Hairline"
                            palette.buttonText: settings.settingsAspWide === 1 ? "white" : "gray"
                            //palette.buttonText: window.cameraAspWide === 1 ? "white" : "gray"

                            background: Rectangle {
                                width: 60 * window.scalingRatio
                                height: 35 * window.scalingRatio
                                anchors.centerIn: parent
                                color: "transparent"
                                border.width: 1 * window.scalingRatio
                                border.color: "white"
                                radius: 6 * window.scalingRatio
                            }

                            onClicked: {
                                // camera.aspWide = 1;
                                settings.settingsAspWide = 1;
                                configBar.aspectRatioOpened = 0;
                                window.cameraChangeResolution(fourThreeButton.text)
                            }
                        }

                        Button {
                            id: fourThreeButton
                            text: "4:3"
                            Layout.preferredWidth: 60 * window.scalingRatio
                            font.pixelSize:  35 * window.scalingRatio * 0.5
                            font.bold: true
                            font.family: "Lato Hairline"
                            palette.buttonText: settings.settingsAspWide === 1 ? "gray" : "white"

                            background: Rectangle {
                                width: 60 * window.scalingRatio
                                height: 35 * window.scalingRatio
                                anchors.centerIn: parent
                                color: "transparent"
                                border.width: 1 * window.scalingRatio
                                border.color: "white"
                                radius: 6 * window.scalingRatio
                            }

                            onClicked: {
                                //camera.aspWide = 0;
                                settings.settingsAspWide = 0;
                                configBar.aspectRatioOpened = 0;
                                window.cameraChangeResolution(fourThreeButton.text)
                            }
                        }

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 300
                                easing.type: Easing.InOutQuad
                            }
                        }

                        onVisibleChanged: {
                            opacity = visible ? 1 : 0
                        }
                    }
                }

                Button {
                    id: menu
                    icon.source: "icons/menu.svg"
                    icon.height: configBarDrawer.height * 0.6
                    icon.width: configBarDrawer.height * 0.6
                    icon.color: "white"
                    enabled: !window.videoCaptured

                    background: Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                    }

                    onClicked: {
                        backCamSelect.visible = true
                        optionContainer.state = "opened"
                        configBarDrawer.close()
                        window.blurView = 1
                    }
                }
            }
        }

        onClosed: {
            window.blurView = optionContainer.state === "opened" ? 1 : 0;
            configBar.opened = 0;
            configBar.aspectRatioOpened = 0;
        }
    }

    Button {
        id: configBarBtn
        icon.source: configBarDrawer.position == 0.0 ?  "icons/goDownSymbolic.svg" : ""
        icon.height: configBarDrawer.height * 0.5
        icon.width: configBarDrawer.height * 0.7
        icon.color: "white"

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 10 * window.scalingRatio

        visible: !mediaView.visible
        flat: true
        down: false

        onClicked: {
            configBarDrawer.open()
        }
    }

    Button {
        text: cameraLoader.active ? "Unload Camera" : "Load Camera"
        anchors.centerIn: parent
        onClicked: {
            window.stopCamera()

            cameraLoader.active = !cameraLoader.active
        }
    }
}
