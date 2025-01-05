// SPDX-License-Identifier: GPL-2.0-only
// Copyright (C) 2024 Furi Labs
//
// Authors:
// Bardia Moshiri <bardia@furilabs.com>
// Joaquin Philco <joaquinphilco@gmail.com>

#include <QtCore/QtGlobal>

#ifdef signals
#undef signals
#endif

#include <gio/gio.h>
#include "appcontroller.h"
#include "flashlightcontroller.h"
#include "filemanager.h"
#include "thumbnailgenerator.h"
#include "qrcodehandler.h"
#include "settingsmanager.h"
#include "zxingreader.h"
#include <QQmlContext>
#include <QQuickItem>
#include <QCamera>

AppController::AppController(QApplication& app)
    : m_app(app), m_engine(nullptr), m_window(nullptr),
      m_flashlightController(nullptr), m_fileManager(nullptr),
      m_thumbnailGenerator(nullptr), m_qrCodeHandler(nullptr),
      m_hidden_window(false)
{
    setup_gsettings_listener();
}

AppController::~AppController()
{
    delete m_engine;
    delete m_flashlightController;
    delete m_fileManager;
    delete m_thumbnailGenerator;
    delete m_qrCodeHandler;
}

void AppController::initialize()
{
    m_engine = new QQmlApplicationEngine();
    setupEngine();
    loadMainWindow();
}

void AppController::check_gsettings_background() {
    GError *error = nullptr;

    GSettings *settings = g_settings_new("io.furios.camera");
    if (!settings) {
        qDebug() << "Error: Failed to create GSettings object.";
        return;
    }

    gboolean value = g_settings_get_boolean(settings, "camera-background");
    g_object_unref(settings);

    if (!value && m_hidden_window) {
        QTimer::singleShot(0, QCoreApplication::instance(), &QCoreApplication::quit);
    }
}

void AppController::setup_gsettings_listener() {
    GSettings *settings = g_settings_new("io.furios.camera");
    if (!settings) {
        qDebug() << "Error: Failed to create GSettings object.";
        return;
    }

    g_signal_connect(settings, "changed::camera-background", G_CALLBACK(on_gsettings_changed), this);
}

void AppController::on_gsettings_changed(GSettings *settings, const gchar *key, gpointer user_data) {
    if (QString(key) == "camera-background") {
        gboolean new_value = g_settings_get_boolean(settings, key);
        AppController *self = static_cast<AppController *>(user_data);
        self->check_gsettings_background();
    }
}

void AppController::hideWindow()
{
    m_hidden_window = true;
    if (m_window) {
        // The camera is already unloaded in QML before this slot is called
        m_fileManager->turnOffGps();
        m_window->hide();
        check_gsettings_background();
    }
}

void AppController::showWindow()
{
    m_hidden_window = false;
    if (m_window) {
        loadCamera(); // Before showing window, load back the camera

        AppController::restartGpsIfNeeded();
        m_window->show();
        m_window->raise();
        m_window->requestActivate();
    }
}

void AppController::loadCamera() {
    QObject *rootObject = m_engine->rootObjects().first();
    QObject *camera = rootObject->findChild<QObject*>("cameraLoader");

    if (camera) {
        camera->setProperty("active", true);
        qDebug() << "Camera state set to Active";
    }
}

void AppController::initializeSettings()
{
    if (m_engine) {
        SettingsManager::instance().initialize(m_engine);
    }
}

void AppController::createDirectories()
{
    if (m_fileManager) {
        m_fileManager->createDirectory(QString("/Pictures/furios-camera"));
        m_fileManager->createDirectory(QString("/Videos/furios-camera"));
    }
}

void AppController::restartGpsIfNeeded()
{
    if (m_fileManager && SettingsManager::instance().gpsOn()) {
        m_fileManager->restartGps();
    }
}

void AppController::setupEngine()
{
    m_flashlightController = new FlashlightController();
    m_fileManager = new FileManager();
    m_thumbnailGenerator = new ThumbnailGenerator();
    m_qrCodeHandler = new QRCodeHandler();

    m_engine->rootContext()->setContextProperty("flashlightController", m_flashlightController);
    m_engine->rootContext()->setContextProperty("fileManager", m_fileManager);
    m_engine->rootContext()->setContextProperty("thumbnailGenerator", m_thumbnailGenerator);
    m_engine->rootContext()->setContextProperty("QRCodeHandler", m_qrCodeHandler);

    ZXingQt::registerQmlAndMetaTypes();
}

void AppController::loadMainWindow()
{
    const QUrl url(QStringLiteral("qrc:/main.qml"));
    QObject::connect(m_engine, &QQmlApplicationEngine::objectCreated,
                     &m_app, [this, url](QObject *obj, const QUrl &objUrl) {
        if (!obj && url == objUrl)
            QCoreApplication::exit(-1);
        if (auto window = qobject_cast<QQuickWindow*>(obj)) {
            m_window = window;
            window->setFlag(Qt::Window);

            QObject::connect(window, SIGNAL(customClosing()), this, SLOT(hideWindow()));
        }
    }, Qt::QueuedConnection);

    m_engine->load(url);
}