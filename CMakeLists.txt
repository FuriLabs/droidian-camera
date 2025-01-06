cmake_minimum_required(VERSION 3.16)
project (furios-camera LANGUAGES CXX)

set(CMAKE_INCLUDE_CURRENT_DIR ON)

set(CMAKE_AUTOUIC ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt5 REQUIRED COMPONENTS Core DBus Widgets Quick Qml Multimedia)
find_package(exiv2 REQUIRED)

find_package(PkgConfig REQUIRED)
pkg_check_modules(GLIB REQUIRED glib-2.0 gio-2.0)

execute_process(COMMAND pkg-config --cflags gstreamer-1.0 OUTPUT_VARIABLE GST_CFLAGS OUTPUT_STRIP_TRAILING_WHITESPACE)
execute_process(COMMAND pkg-config --libs gstreamer-1.0 OUTPUT_VARIABLE GST_LIBS OUTPUT_STRIP_TRAILING_WHITESPACE)

execute_process(COMMAND pkg-config --variable=libdir glib-2.0 OUTPUT_VARIABLE GLIB_LIBDIR OUTPUT_STRIP_TRAILING_WHITESPACE)

include_directories(/usr/include/ZXing)

set(APP_SOURCES
		${CMAKE_SOURCE_DIR}/src/main.cpp
		${CMAKE_SOURCE_DIR}/src/thumbnailgenerator.cpp
		${CMAKE_SOURCE_DIR}/src/flashlightcontroller.cpp
		${CMAKE_SOURCE_DIR}/src/filemanager.cpp
		${CMAKE_SOURCE_DIR}/src/exif.cpp
		${CMAKE_SOURCE_DIR}/src/qrcodehandler.cpp
		${CMAKE_SOURCE_DIR}/src/geocluefind.cpp
		${CMAKE_SOURCE_DIR}/src/singleinstance.cpp
		${CMAKE_SOURCE_DIR}/src/windoweventfilter.cpp
		${CMAKE_SOURCE_DIR}/src/appcontroller.cpp
		${CMAKE_SOURCE_DIR}/src/settingsmanager.cpp)

set(APP_HEADERS
		${CMAKE_SOURCE_DIR}/src/filemanager.h
		${CMAKE_SOURCE_DIR}/src/flashlightcontroller.h
		${CMAKE_SOURCE_DIR}/src/thumbnailgenerator.h
		${CMAKE_SOURCE_DIR}/src/zxingreader.h
		${CMAKE_SOURCE_DIR}/src/exif.h
		${CMAKE_SOURCE_DIR}/src/qrcodehandler.h
		${CMAKE_SOURCE_DIR}/src/geocluefind.h
		${CMAKE_SOURCE_DIR}/src/singleinstance.h
		${CMAKE_SOURCE_DIR}/src/windoweventfilter.h
		${CMAKE_SOURCE_DIR}/src/appcontroller.h
		${CMAKE_SOURCE_DIR}/src/settingsmanager.h)

qt5_add_resources(APP_RESOURCES
	${CMAKE_SOURCE_DIR}/sounds/sounds.qrc
	${CMAKE_SOURCE_DIR}/icons/icons.qrc
	${CMAKE_SOURCE_DIR}/src/qml/qml.qrc)

add_executable(${PROJECT_NAME} ${APP_SOURCES} ${APP_HEADERS} ${APP_RESOURCES})

target_include_directories(${PROJECT_NAME} PUBLIC
    /usr/include/gstreamer-1.0
    /usr/include/glib-2.0
    ${GLIB_LIBDIR}/glib-2.0/include
    ${GLIB_INCLUDE_DIRS}
)

target_compile_options(${PROJECT_NAME} PUBLIC ${GST_CFLAGS})
target_link_libraries(${PROJECT_NAME} PUBLIC Qt5::Core Qt5::Widgets Qt5::Quick Qt5::Qml Qt5::Multimedia Qt5::DBus ZXing exiv2 ${GST_LIBS} ${GLIB_LIBRARIES})

install(TARGETS ${PROJECT_NAME} DESTINATION /usr/bin)
install(FILES ${CMAKE_SOURCE_DIR}/furios-camera.desktop DESTINATION /usr/share/applications)
install(FILES ${CMAKE_SOURCE_DIR}/camera-app.svg DESTINATION /usr/share/icons)
install(FILES ${CMAKE_SOURCE_DIR}/furios-camera.conf DESTINATION /etc)
install(FILES ${CMAKE_SOURCE_DIR}/extra/furios-camera-radio.pkla DESTINATION /etc/polkit-1/localauthority/10-vendor.d)
