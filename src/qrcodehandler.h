// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2024 Droidian Project
// Copyright (C) 2024 Furi Labs
//
// Authors:
// Joaquin Philco <joaquinphilco@gmail.com>

#ifndef QRCODEHANDLER_H
#define QRCODEHANDLER_H

#include <QObject>
#include <QDBusMessage>
#include <QVariant>

#define NO_ROUTE_SIGNAL QString("icons/network-wireless-signal-no-route.svg")
#define OFFLINE_SIGNAL QString("icons/network-wireless-signal-offline.svg")
#define NONE_SIGNAL QString("icons/network-wireless-signal-none.svg")
#define WEAK_SIGNAL QString("icons/network-wireless-signal-weak.svg")
#define OK_SIGNAL QString("icons/network-wireless-signal-ok.svg")
#define GOOD_SIGNAL QString("icons/network-wireless-signal-good.svg")
#define EXCELLENT_SIGNAL QString("icons/network-wireless-signal-excellent.svg")

typedef QMap<QString, QVariantMap> Connection;

class QRCodeHandler : public QObject {
    Q_OBJECT

public:
    explicit QRCodeHandler(QObject *parent = nullptr);
    Q_INVOKABLE QString parseQrString(const QString &qrString);
    Q_INVOKABLE void openUrlInFirefox(const QString &url);
    Q_INVOKABLE void connectToWifi();
    Q_INVOKABLE QVariant checkQRCodeInMedia(const QString &currUrl);
    bool forgetConnection();
    bool deactivateConnection();
    quint8 getSignalStrength(const QString &ap);
    QList<QString> getWiFiDevices();
    bool scanWiFiAccessPoints();
    Q_INVOKABLE QString getWifiId();
    Q_INVOKABLE QString getSignalStrengthIcon();
    bool getWiFiEnabled();
    quint8 scanWiFiAccessPointsForSignalStrength();

public slots:
    void onAccessPointAdded(const QDBusMessage &message);

private:
    QString protocol = "";
    QString ssid = "";
    QString password = "";
    QString WiFiDevice = "";
    int accessPointAddedCalled = 0;
};

#endif // QRCODEHANDLER_H
