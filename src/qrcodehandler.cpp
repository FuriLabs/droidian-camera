// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2024 Droidian Project
// Copyright (C) 2024 Furi Labs
//
// Authors:
// Joaquin Philco <joaquinphilco@gmail.com>

#include "qrcodehandler.h"
#include "zxingreader.h"
#include <QProcess>
#include <QImage>
#include <cstdlib>
#include <iostream>
#include <QRegularExpression>
#include <QUrl>
#include <QDebug>
#include <QtDBus>
#include <QDBusConnection>
#include <QDBusMessage>

using ZXing::ReaderOptions;
using ZXing::Position;
using ZXing::Result;

QRegularExpression urlPattern("^(?:http(s)?://)?[\\w.-]+(?:\\.[\\w.-]+)+[\\w\\-._~:/?#[\\]@!$&'()*+,;=]*$");
QRegularExpression wifiPattern("^WIFI:S:([^;]+);T:([^;]+);P:([^;]+)");

QRCodeHandler::QRCodeHandler(QObject *parent) : QObject(parent) {
    const char* waylandDisplay = getenv("WAYLAND_DISPLAY");

    if (waylandDisplay == nullptr) {
        setenv("WAYLAND_DISPLAY", "wayland-0", 1);
        std::cout << "WAYLAND_DISPLAY was not set. It is now set to 'wayland-0'." << std::endl;
    } else {
        std::cout << "WAYLAND_DISPLAY is already set to '" << waylandDisplay << "'." << std::endl;
    }
}

QString QRCodeHandler::parseQrString(const QString &qrString) {
    QString mutableQrString = qrString;

    if (urlPattern.match(mutableQrString).hasMatch()) {
        return QString("URL");
    } else if (wifiPattern.match(mutableQrString).hasMatch()) {
        QString mutableCredentials = qrString;

        QRegularExpressionMatch match = wifiPattern.match(mutableCredentials);
        ssid = match.captured(1);
        protocol = match.captured(2);
        password = match.captured(3);

        return QString("WIFI");
    } else {
        qDebug() << "Invalid QR string: " << qrString;
    }
    return QString("");
}

void QRCodeHandler::openUrlInFirefox(const QString &url) {
    QString mutableUrl = url;

    if (!mutableUrl.startsWith("http://") && !mutableUrl.startsWith("https://")) {
        mutableUrl.prepend("http://");
    }
    QProcess::startDetached("xdg-open", QStringList() << mutableUrl);
}

void QRCodeHandler::connectToWifi() {
    QDBusInterface wifiEnabled("org.freedesktop.NetworkManager",
                               "/org/freedesktop/NetworkManager",
                               "org.freedesktop.DBus.Properties",
                               QDBusConnection::systemBus());

    if (!wifiEnabled.isValid()) {
        qWarning() << "Failed to connect to dbus";
        return;
    }

    qDBusRegisterMetaType<Connection>();

    Connection connection;

    if (!QRCodeHandler::deactivateConnection()) {
        qWarning() << "Failed to deactivate connection";
        QDBusConnection::systemBus().disconnectFromBus(QDBusConnection::systemBus().name());
        return;
    }

    if (!QRCodeHandler::forgetConnection()) {
        qWarning() << "Failed to forget connection";
        QDBusConnection::systemBus().disconnectFromBus(QDBusConnection::systemBus().name());
        return;
    }

    // Enable WiFi by setting WirelessEnabled to true (RF kill switch)
    QDBusReply<void> reply = wifiEnabled.call("Set", "org.freedesktop.NetworkManager", "WirelessEnabled", QVariant::fromValue(QDBusVariant(QVariant(true))));

    if (!reply.isValid()) {
        qWarning() << "Failed to turn on wifi: " << reply.error().name() + " : " + reply.error().message();
        QDBusConnection::systemBus().disconnectFromBus(QDBusConnection::systemBus().name());
        return;
    } else {
        qDebug() << "Successfully turned on wifi";
    }

    connection["connection"]["type"] = "802-11-wireless";
    connection["connection"]["uuid"] = QUuid::createUuid().toString().remove('{').remove('}');
    connection["connection"]["id"] = ssid;
    connection["connection"]["autoconnect-retries"] = -1;

    connection["802-11-wireless"]["ssid"] = ssid.toUtf8();
    connection["802-11-wireless"]["hidden"] = false;
    connection["802-11-wireless"]["mode"] = "infrastructure";

    if (!password.isEmpty()) {
        connection["802-11-wireless-security"]["key-mgmt"] = "wpa-psk";
        connection["802-11-wireless-security"]["auth-alg"] = "open";
        connection["802-11-wireless-security"]["psk"] = password;
    } else {
        connection["802-11-wireless-security"]["key-mgmt"] = "none";
    }

    connection["ipv4"]["method"] = "auto";
    connection["ipv4"]["dns-priority"] = 600;
    connection["ipv6"]["method"] = "ignore";

    QDBusInterface nmSettings("org.freedesktop.NetworkManager",
                              "/org/freedesktop/NetworkManager/Settings",
                              "org.freedesktop.NetworkManager.Settings",
                              QDBusConnection::systemBus());

    if (!nmSettings.isValid()) {
        qWarning() << "Failed to connect to dbus";
        QDBusConnection::systemBus().disconnectFromBus(QDBusConnection::systemBus().name());
        return;
    }

    // Add the connection
    QDBusReply<QDBusObjectPath> result = nmSettings.call("AddConnection", QVariant::fromValue(connection));

    if (!result.isValid()) {
       qWarning() << "Error adding connection: " << result.error().name() << " : " << result.error().message();
    } else {
       qDebug() << "Added: " << result.value().path();
       qDebug() << "Connection added successfully";
    }

    accessPointAddedCalled = 0;
    QList<QString> devices = QRCodeHandler::getWiFiDevices();

    if (!devices.isEmpty()) {
        WiFiDevice = devices.at(0);
        QDBusConnection::systemBus().connect(
            "org.freedesktop.NetworkManager",
            WiFiDevice,
            "org.freedesktop.NetworkManager.Device.Wireless",
            "AccessPointAdded",
            this,
            SLOT(onAccessPointAdded(QDBusMessage))
        );
    }

    QDBusConnection::systemBus().disconnectFromBus(QDBusConnection::systemBus().name());
}

bool QRCodeHandler::forgetConnection() {
    qDBusRegisterMetaType<Connection>;

    QDBusInterface nmSettings("org.freedesktop.NetworkManager",
                              "/org/freedesktop/NetworkManager/Settings",
                              "org.freedesktop.NetworkManager.Settings",
                              QDBusConnection::systemBus());

    if (!nmSettings.isValid()) {
        qWarning() << "Failed to connect to dbus";
        return false;
    }

    QDBusReply<QList<QDBusObjectPath>> reply = nmSettings.call("ListConnections");

    if (!reply.isValid()) {
        qWarning() << "Failed to list connections" << reply.error().message();
        return false;
    }

    QList<QDBusObjectPath> connectionsPaths = reply.value();
    bool ssidFound = false;

    for (const QDBusObjectPath &path: connectionsPaths) {
        QDBusInterface connectionSettings("org.freedesktop.NetworkManager",
                                          path.path(),
                                          "org.freedesktop.NetworkManager.Settings.Connection",
                                          QDBusConnection::systemBus());

        if (!connectionSettings.isValid()) {
            qWarning() << "Failed to connect to dbus";
            return false;
        }

        QDBusReply<Connection> settingsReply = connectionSettings.call("GetSettings");
        if (!settingsReply.isValid()) {
            qWarning() << "Failed to get settings for connection:" << path.path();
            continue;
        }

        QMap<QString, QVariantMap> settings = settingsReply.value();
        QString type = settings["connection"]["type"].toString();

        if (type == "802-11-wireless") {
            QString connectionSsid = settings["802-11-wireless"]["ssid"].toString();

            if (connectionSsid == ssid) {
                ssidFound = true;
                QDBusReply<void> deleteReply = connectionSettings.call("Delete");

                if (!deleteReply.isValid()) {
                    qWarning() << "Failed to delete connection:" << path.path();
                    return false;
                } else {
                    qDebug() << "Successfully deleted connection with SSID:" << ssid;
                    // break; not sure if this is a good idea ??
                }
            }
        }
    }

    if (!ssidFound) {
        qDebug() << "SSID not found in the list of connections. Proceeding.";
    }

    QDBusConnection::systemBus().disconnectFromBus(QDBusConnection::systemBus().name());
    return true;
}

bool QRCodeHandler::deactivateConnection() {
    QDBusInterface nmProperties("org.freedesktop.NetworkManager",
                                "/org/freedesktop/NetworkManager",
                                "org.freedesktop.DBus.Properties",
                                QDBusConnection::systemBus());

    if (!nmProperties.isValid()) {
        qWarning() << "Failed to connect to dbus";
        return false;
    }

    QDBusInterface nmInterface("org.freedesktop.NetworkManager",
                               "/org/freedesktop/NetworkManager",
                               "org.freedesktop.NetworkManager",
                               QDBusConnection::systemBus());

    if (!nmInterface.isValid()) {
        qWarning() << "Failed to connect to dbus";
        return false;
    }

    QDBusMessage reply = nmProperties.call("Get", "org.freedesktop.NetworkManager", "ActiveConnections");

    if (reply.type() != QDBusMessage::ReplyMessage) {
        qWarning() << "DBus query failed! reply.type() != QDBusMessage::ReplyMessage";
        return false;
    }

    QList<QVariant> outArgs = reply.arguments();
    QVariant first = outArgs.at(0);
    QDBusVariant dbvFirst = first.value<QDBusVariant>();
    QVariant vFirst = dbvFirst.variant();
    QDBusArgument dbusArgs = vFirst.value<QDBusArgument>();

    QDBusObjectPath objPath;
    bool deactivated = false;

    dbusArgs.beginArray();
    while (!dbusArgs.atEnd()) {
        dbusArgs >> objPath;
        qDebug() <<"Active connection path is: "<< objPath.path();

        QDBusInterface activeConnectionProperties("org.freedesktop.NetworkManager",
                                                  objPath.path(),
                                                  "org.freedesktop.DBus.Properties",
                                                  QDBusConnection::systemBus());

        if (!activeConnectionProperties.isValid()) {
            qWarning() << "Failed to connect to dbus";
            return false;
        }

        QDBusReply<QVariant> reply = activeConnectionProperties.call("Get", "org.freedesktop.NetworkManager.Connection.Active", "Type");

        if (!reply.isValid()) {
            qDebug() << "Failed to retrieve active connection type. Error:" << reply.error().message();
        } else {
            QString activeType = reply.value().toString();
            qDebug() << "Active connection type is: " << activeType;

            if (activeType == "802-11-wireless")  {
                QDBusReply<void> deactivateReply = nmInterface.call("DeactivateConnection", QVariant::fromValue(objPath));

                if (!deactivateReply.isValid()) {
                    qWarning() << "Failed to deactivate path: " << objPath.path() << " " << deactivateReply.error().name() << " : " << reply.error().message();
                    QDBusConnection::systemBus().disconnectFromBus(QDBusConnection::systemBus().name());
                    return false;
                } else {
                    qDebug() << "Deactivated path: " << objPath.path() << " successfully";
                    deactivated = true;
                }
            }
        }
    }

    if (!deactivated) {
        qDebug() << "No wireless connection was deactivated. Proceeding.";
    }

    dbusArgs.endArray();
    QDBusConnection::systemBus().disconnectFromBus(QDBusConnection::systemBus().name());
    return true;
}

void QRCodeHandler::onAccessPointAdded(const QDBusMessage &message) {
    if (++accessPointAddedCalled > 1) {
        QDBusConnection::systemBus().disconnectFromBus(QDBusConnection::systemBus().name());
        return;
    }

    if (!QRCodeHandler::scanWiFiAccessPoints()) {
        qWarning() << "Failed to get signal strength"; // ither failed or signal strength is 0
    }

    QDBusConnection::systemBus().disconnect(
        "org.freedesktop.NetworkManager",
        WiFiDevice,
        "org.freedesktop.NetworkManager.Device.Wireless",
        "AccessPointAdded",
        this,
        SLOT(onAccessPointAdded(QDBusMessage))
    );

    QDBusConnection::systemBus().disconnectFromBus(QDBusConnection::systemBus().name());
}

quint8 QRCodeHandler::getSignalStrength(const QString &ap) {
    QDBusInterface device("org.freedesktop.NetworkManager",
                          ap,
                          "org.freedesktop.NetworkManager.AccessPoint",
                          QDBusConnection::systemBus());

    if (!device.isValid()) {
        qWarning() << "Failed to connect to dbus";
        QDBusConnection::systemBus().disconnectFromBus(QDBusConnection::systemBus().name());
        return 0;
    }

    QVariant getStrength = device.property("Strength");

    if (!getStrength.isValid()) {
        qWarning() << "Failed to connect to dbus";
        QDBusConnection::systemBus().disconnectFromBus(QDBusConnection::systemBus().name());
        return 0;
    }

    quint8 strength = getStrength.toUInt();
    qDebug() << "Strength: " << strength;

    QDBusConnection::systemBus().disconnectFromBus(QDBusConnection::systemBus().name());
    return strength;
}

QList<QString> QRCodeHandler::getWiFiDevices() {
    QDBusInterface nmInterface("org.freedesktop.NetworkManager",
                               "/org/freedesktop/NetworkManager",
                               "org.freedesktop.NetworkManager",
                               QDBusConnection::systemBus());

    if (!nmInterface.isValid()) {
        qWarning() << "Failed to connect to dbus";
        QDBusConnection::systemBus().disconnectFromBus(QDBusConnection::systemBus().name());
        return QList<QString>();
    }

    QDBusReply<QList<QDBusObjectPath>> reply = nmInterface.call("GetDevices");
    if (!reply.isValid()) {
        qWarning() << "Failed to get devices";
        QDBusConnection::systemBus().disconnectFromBus(QDBusConnection::systemBus().name());
        return QList<QString>();
    }

    QList<QString> devices;
    for (const QDBusObjectPath &path: reply.value()) {
        QDBusInterface device("org.freedesktop.NetworkManager",
                              path.path(),
                              "org.freedesktop.NetworkManager.Device",
                              QDBusConnection::systemBus());

        QVariant deviceType = device.property("DeviceType");

        if (!deviceType.isValid()) {
            continue;
        } else if (deviceType.toUInt() == 2) {
            devices.append(path.path());
        }
    }

    QDBusConnection::systemBus().disconnectFromBus(QDBusConnection::systemBus().name());
    return devices;
}

bool QRCodeHandler::scanWiFiAccessPoints() {
    QList<QString> WiFiDevices = QRCodeHandler::getWiFiDevices();

    if (!WiFiDevices.isEmpty()) {
        QString device = WiFiDevices.at(0);

        QDBusInterface WiFi("org.freedesktop.NetworkManager",
                            device,
                            "org.freedesktop.NetworkManager.Device.Wireless",
                            QDBusConnection::systemBus());

        QDBusReply<QList<QDBusObjectPath>> ap = WiFi.call("GetAllAccessPoints");

        if (!ap.isValid()) {
            qWarning() << "Failed to get Access Points";
            QDBusConnection::systemBus().disconnectFromBus(QDBusConnection::systemBus().name());
            return false;
        }

        for (const QDBusObjectPath &apPath: ap.value()) {
            QDBusInterface apInterface("org.freedesktop.NetworkManager",
                                       apPath.path(),
                                       "org.freedesktop.NetworkManager.AccessPoint",
                                       QDBusConnection::systemBus());

            QVariant reply = apInterface.property("Ssid");
            qDebug() << "Access Point: " << apPath.path();

            if (reply.isValid()) {
                QString apSsid = QString::fromUtf8(reply.toByteArray());

                if (apSsid == ssid) {
                    qDebug() << "Access Point Ssid: " << apSsid;
                    getSignalStrength(apPath.path());
                    return true;
                }

            } else {
                qWarning() << "Failed to get SSID of Access Point: " << apPath.path();
                QDBusConnection::systemBus().disconnectFromBus(QDBusConnection::systemBus().name());
                return false;
            }
        }
    }

    QDBusConnection::systemBus().disconnectFromBus(QDBusConnection::systemBus().name());
    return false;
}

quint8 QRCodeHandler::scanWiFiAccessPointsForSignalStrength() {
    QList<QString> WiFiDevices = QRCodeHandler::getWiFiDevices();

    if (!WiFiDevices.isEmpty()) {
        QString device = WiFiDevices.at(0);

        QDBusInterface WiFi("org.freedesktop.NetworkManager",
                            device,
                            "org.freedesktop.NetworkManager.Device.Wireless",
                            QDBusConnection::systemBus());

        QDBusReply<QList<QDBusObjectPath>> ap = WiFi.call("GetAllAccessPoints");

        if (!ap.isValid()) {
            qWarning() << "Failed to get Access Points";
            QDBusConnection::systemBus().disconnectFromBus(QDBusConnection::systemBus().name());
            return 0;
        }

        for (const QDBusObjectPath &apPath: ap.value()) {
            QDBusInterface apInterface("org.freedesktop.NetworkManager",
                                       apPath.path(),
                                       "org.freedesktop.NetworkManager.AccessPoint",
                                       QDBusConnection::systemBus());

            QVariant reply = apInterface.property("Ssid");
            qDebug() << "Access Point: " << apPath.path();

            if (reply.isValid()) {
                QString apSsid = QString::fromUtf8(reply.toByteArray());

                if (apSsid == ssid) {
                    qDebug() << "Access Point Ssid: " << apSsid;

                    return getSignalStrength(apPath.path());
                }

            } else {
                qWarning() << "Failed to get SSID of Access Point: " << apPath.path();
                QDBusConnection::systemBus().disconnectFromBus(QDBusConnection::systemBus().name());
                return 0;
            }
        }
    }

    QDBusConnection::systemBus().disconnectFromBus(QDBusConnection::systemBus().name());
    return 0;
}

bool QRCodeHandler::getWiFiEnabled() {
    QDBusInterface wifi("org.freedesktop.NetworkManager",
                        "/org/freedesktop/NetworkManager",
                        "org.freedesktop.NetworkManager",
                        QDBusConnection::systemBus());

    if (!wifi.isValid()) {
        qWarning() << "Failed to connect to dbus";
        QDBusConnection::systemBus().disconnectFromBus(QDBusConnection::systemBus().name());
        return false;
    }

    QVariant reply = wifi.property("WirelessEnabled");

    if (!reply.isValid()) {
        qWarning() << "Failed to get WirelessEnabled";
        QDBusConnection::systemBus().disconnectFromBus(QDBusConnection::systemBus().name());
        return false;
    }

    bool enabled = reply.toBool();

    QDBusConnection::systemBus().disconnectFromBus(QDBusConnection::systemBus().name());
    return enabled;
}

QString QRCodeHandler::getSignalStrengthIcon() {
    if (!getWiFiEnabled()) {
        return OFFLINE_SIGNAL;
    }

    quint8 strength = scanWiFiAccessPointsForSignalStrength();

    if (strength <= 0)
        return NO_ROUTE_SIGNAL;
    else if (strength < 20)
        return NONE_SIGNAL;
    else if (strength < 40)
        return WEAK_SIGNAL;
    else if (strength < 50)
        return OK_SIGNAL;
    else if (strength < 80)
        return GOOD_SIGNAL;
    else
        return EXCELLENT_SIGNAL;
}

QString QRCodeHandler::getWifiId() {
    return ssid;
}

QVariant QRCodeHandler::checkQRCodeInMedia(const QString &currUrl) {
    QVariantMap resultMap;
    QString filePath = currUrl;
    int colonIndex = filePath.indexOf(':');

    if (colonIndex != -1) {
        filePath.remove(0, colonIndex + 1);
    }

    QImage image;

    if (!image.load(filePath)) {
        qDebug() << "Failed to load image from" << filePath;
        resultMap["text"] = "";
        resultMap["isValid"] = false;
        resultMap["position"] = QVariantMap();
        return resultMap;
    }

    ReaderOptions opts;
    opts.setMaxNumberOfSymbols(1);

    auto ImgFmtFromQImg = [](const QImage& img) {
        switch (img.format()) {
            case QImage::Format_ARGB32:
            case QImage::Format_RGB32:
#if Q_BYTE_ORDER == Q_LITTLE_ENDIAN
                return ZXing::ImageFormat::BGRX;
#else
                return ZXing::ImageFormat::XRGB;
#endif
            case QImage::Format_RGB888: return ZXing::ImageFormat::RGB;
            case QImage::Format_RGBX8888:
            case QImage::Format_RGBA8888: return ZXing::ImageFormat::RGBX;
            case QImage::Format_Grayscale8: return ZXing::ImageFormat::Lum;
            default: return ZXing::ImageFormat::None;
        }
    };

    ZXing::ImageFormat format = ImgFmtFromQImg(image);
    if (format == ZXing::ImageFormat::None) {
        qDebug() << "Unsupported image format.";
        resultMap["text"] = "";
        resultMap["isValid"] = false;
        resultMap["position"] = QVariantMap();
        return resultMap;
    }

    ZXing::ImageView imageView({image.bits(), image.width(), image.height(), format, static_cast<int>(image.bytesPerLine())});
    Result qResults = ZXing::ReadBarcode(imageView, opts);

    resultMap["text"] = QString::fromStdString(qResults.text());
    resultMap["isValid"] = qResults.isValid();

    QVariantMap positionMap;
    positionMap["topLeft"] = QVariantMap{
        {"x", qResults.position().topLeft().x},
        {"y", qResults.position().topLeft().y}
    };
    positionMap["topRight"] = QVariantMap{
        {"x", qResults.position().topRight().x},
        {"y", qResults.position().topRight().y}
    };
    positionMap["bottomRight"] = QVariantMap{
        {"x", qResults.position().bottomRight().x},
        {"y", qResults.position().bottomRight().y}
    };
    positionMap["bottomLeft"] = QVariantMap{
        {"x", qResults.position().bottomLeft().x},
        {"y", qResults.position().bottomLeft().y}
    };

    resultMap["position"] = positionMap;
    resultMap["readWidth"] = image.width();
    resultMap["readHeight"] = image.height();

    return resultMap;
}