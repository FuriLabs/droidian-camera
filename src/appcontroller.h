// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2024 Furi Labs
//
// Authors:
// Bardia Moshiri <bardia@furilabs.com>
// Joaquin Philco <joaquin@furilabs.com>

#ifndef APPCONTROLLER_H
#define APPCONTROLLER_H

#include <QtCore/QtGlobal>

#ifdef signals
#undef signals
#endif

#include <gio/gio.h>
#include <QObject>
#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQuickWindow>
#include <QSystemTrayIcon>

class FlashlightController;
class FileManager;
class ThumbnailGenerator;
class QRCodeHandler;

class AppController : public QObject
{
    Q_OBJECT
public:
    explicit AppController(QApplication& app);
    ~AppController();

    void initialize();
    void showWindow();
    void loadCamera();
    void initializeSettings();
    void createDirectories();
    void restartGpsIfNeeded();
    void check_gsettings_background();
    void setup_gsettings_listener();

public slots:
    void hideWindow();

private:
    static void on_gsettings_changed(GSettings *settings, const gchar *key, gpointer user_data);
    void setupEngine();
    void loadMainWindow();

    bool m_hidden_window;
    QApplication& m_app;
    QQmlApplicationEngine* m_engine;
    QQuickWindow* m_window;
    QSystemTrayIcon* m_trayIcon;
    FlashlightController* m_flashlightController;
    FileManager* m_fileManager;
    ThumbnailGenerator* m_thumbnailGenerator;
    QRCodeHandler* m_qrCodeHandler;
};

#endif // APPCONTROLLER_H
