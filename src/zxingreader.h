/*
 * Copyright 2020 Axel Waggershauser
 * Copyright 2024 Bardia Moshiri
 */
// SPDX-License-Identifier: Apache-2.0

#pragma once

#include <ReadBarcode.h>

#include <QImage>
#include <QDebug>
#include <QMetaType>
#include <QScopeGuard>
#include <QQmlEngine>
#include <algorithm>

#if QT_VERSION < QT_VERSION_CHECK(6, 0, 0)
#include <QAbstractVideoFilter>
#else
#include <QVideoFrame>
#include <QVideoSink>
#endif

#include <QElapsedTimer>
#include <QTimer>
#include <QtConcurrent/QtConcurrent>

namespace ZXingQt {

Q_NAMESPACE

enum class BarcodeFormat
{
	None            = 0,         ///< Used as a return value if no valid barcode has been detected
	Aztec           = (1 << 0),  ///< Aztec
	Codabar         = (1 << 1),  ///< Codabar
	Code39          = (1 << 2),  ///< Code39
	Code93          = (1 << 3),  ///< Code93
	Code128         = (1 << 4),  ///< Code128
	DataBar         = (1 << 5),  ///< GS1 DataBar, formerly known as RSS 14
	DataBarExpanded = (1 << 6),  ///< GS1 DataBar Expanded, formerly known as RSS EXPANDED
	DataMatrix      = (1 << 7),  ///< DataMatrix
	EAN8            = (1 << 8),  ///< EAN-8
	EAN13           = (1 << 9),  ///< EAN-13
	ITF             = (1 << 10), ///< ITF (Interleaved Two of Five)
	MaxiCode        = (1 << 11), ///< MaxiCode
	PDF417          = (1 << 12), ///< PDF417 or
	QRCode          = (1 << 13), ///< QR Code
	UPCA            = (1 << 14), ///< UPC-A
	UPCE            = (1 << 15), ///< UPC-E
	MicroQRCode     = (1 << 16), ///< Micro QR Code
	RMQRCode        = (1 << 17), ///< Rectangular Micro QR Code

	LinearCodes = Codabar | Code39 | Code93 | Code128 | EAN8 | EAN13 | ITF | DataBar | DataBarExpanded | UPCA | UPCE,
	MatrixCodes = Aztec | DataMatrix | MaxiCode | PDF417 | QRCode | MicroQRCode | RMQRCode,
};

enum class ContentType { Text, Binary, Mixed, GS1, ISO15434, UnknownECI };

using ZXing::ReaderOptions;
using ZXing::Binarizer;
using ZXing::BarcodeFormats;

Q_ENUM_NS(BarcodeFormat)
Q_ENUM_NS(ContentType)

template<typename T, typename = decltype(ZXing::ToString(T()))>
QDebug operator<<(QDebug dbg, const T& v)
{
	return dbg.noquote() << QString::fromStdString(ToString(v));
}

class Position : public ZXing::Quadrilateral<QPoint>
{
	Q_GADGET

	Q_PROPERTY(QPoint topLeft READ topLeft)
	Q_PROPERTY(QPoint topRight READ topRight)
	Q_PROPERTY(QPoint bottomRight READ bottomRight)
	Q_PROPERTY(QPoint bottomLeft READ bottomLeft)

	using Base = ZXing::Quadrilateral<QPoint>;

public:
	using Base::Base;
};

class Result : private ZXing::Result
{
	friend class BarcodeReader;
	Q_GADGET

	Q_PROPERTY(BarcodeFormat format READ format)
	Q_PROPERTY(QString formatName READ formatName)
	Q_PROPERTY(QString text READ text)
	Q_PROPERTY(QByteArray bytes READ bytes)
	Q_PROPERTY(bool isValid READ isValid)
	Q_PROPERTY(ContentType contentType READ contentType)
	Q_PROPERTY(Position position READ position)

	QString _text;
	QByteArray _bytes;

protected:
	Position _position;

public:
	Result() = default; // required for qmetatype machinery

	explicit Result(ZXing::Result&& r) : ZXing::Result(std::move(r)) {
		_text = QString::fromStdString(ZXing::Result::text());
		_bytes = QByteArray(reinterpret_cast<const char*>(ZXing::Result::bytes().data()), Size(ZXing::Result::bytes()));
		auto& pos = ZXing::Result::position();
		auto qp = [&pos](int i) { return QPoint(pos[i].x, pos[i].y); };
		_position = {qp(0), qp(1), qp(2), qp(3)};
	}

	using ZXing::Result::isValid;

	BarcodeFormat format() const { return static_cast<BarcodeFormat>(ZXing::Result::format()); }
	ContentType contentType() const { return static_cast<ContentType>(ZXing::Result::contentType()); }
	QString formatName() const { return QString::fromStdString(ZXing::ToString(ZXing::Result::format())); }
	const QString& text() const { return _text; }
	const QByteArray& bytes() const { return _bytes; }
	const Position& position() const { return _position; }

	// For debugging/development
	int runTime = 0;
	Q_PROPERTY(int runTime MEMBER runTime)
};

inline QList<Result> QListResults(ZXing::Results&& zxres)
{
	QList<Result> res;
	for (auto&& r : zxres)
		res.push_back(Result(std::move(r)));
	return res;
}

inline QList<Result> ReadBarcodes(const QImage& img, const ReaderOptions& opts = {})
{
	using namespace ZXing;

	auto ImgFmtFromQImg = [](const QImage& img) {
		switch (img.format()) {
		case QImage::Format_ARGB32:
		case QImage::Format_RGB32:
#if Q_BYTE_ORDER == Q_LITTLE_ENDIAN
			return ImageFormat::BGRX;
#else
			return ImageFormat::XRGB;
#endif
		case QImage::Format_RGB888: return ImageFormat::RGB;
		case QImage::Format_RGBX8888:
		case QImage::Format_RGBA8888: return ImageFormat::RGBX;
		case QImage::Format_Grayscale8: return ImageFormat::Lum;
		default: return ImageFormat::None;
		}
	};

	auto exec = [&](const QImage& img) {
		return QListResults(ZXing::ReadBarcodes(
			{img.bits(), img.width(), img.height(), ImgFmtFromQImg(img), static_cast<int>(img.bytesPerLine())}, opts));
	};

	return ImgFmtFromQImg(img) == ImageFormat::None ? exec(img.convertToFormat(QImage::Format_Grayscale8)) : exec(img);
}

inline Result ReadBarcode(const QImage& img, const ReaderOptions& opts = {})
{
	auto res = ReadBarcodes(img, ReaderOptions(opts).setMaxNumberOfSymbols(1));
	return !res.isEmpty() ? res.takeFirst() : Result();
}

inline QList<Result> ReadBarcodes(const QVideoFrame& frame, const ReaderOptions& opts = {})
{
	using namespace ZXing;

	ImageFormat fmt = ImageFormat::None;
	int pixStride = 0;
	int pixOffset = 0;

#if QT_VERSION < QT_VERSION_CHECK(6, 0, 0)
#define FORMAT(F5, F6) QVideoFrame::Format_##F5
#define FIRST_PLANE
#else
#define FORMAT(F5, F6) QVideoFrameFormat::Format_##F6
#define FIRST_PLANE 0
#endif

	switch (frame.pixelFormat()) {
	case FORMAT(ARGB32, ARGB8888):
	case FORMAT(ARGB32_Premultiplied, ARGB8888_Premultiplied):
	case FORMAT(RGB32, RGBX8888):
#if Q_BYTE_ORDER == Q_LITTLE_ENDIAN
		fmt = ImageFormat::BGRX;
#else
		fmt = ImageFormat::XRGB;
#endif
		break;

	case FORMAT(BGRA32, BGRA8888):
	case FORMAT(BGRA32_Premultiplied, BGRA8888_Premultiplied):
	case FORMAT(BGR32, BGRX8888):
#if Q_BYTE_ORDER == Q_LITTLE_ENDIAN
		fmt = ImageFormat::RGBX;
#else
		fmt = ImageFormat::XBGR;
#endif
		break;

#if QT_VERSION < QT_VERSION_CHECK(6, 0, 0)
	case QVideoFrame::Format_RGB24: fmt = ImageFormat::RGB; break;
	case QVideoFrame::Format_BGR24: fmt = ImageFormat::BGR; break;
	case QVideoFrame::Format_YUV444: fmt = ImageFormat::Lum, pixStride = 3; break;
#else
	case QVideoFrameFormat::Format_P010:
	case QVideoFrameFormat::Format_P016: fmt = ImageFormat::Lum, pixStride = 1; break;
#endif

	case FORMAT(AYUV444, AYUV):
	case FORMAT(AYUV444_Premultiplied, AYUV_Premultiplied):
#if Q_BYTE_ORDER == Q_LITTLE_ENDIAN
		fmt = ImageFormat::Lum, pixStride = 4, pixOffset = 3;
#else
		fmt = ImageFormat::Lum, pixStride = 4, pixOffset = 2;
#endif
		break;

	case FORMAT(YUV420P, YUV420P):
	case FORMAT(NV12, NV12):
	case FORMAT(NV21, NV21):
	case FORMAT(IMC1, IMC1):
	case FORMAT(IMC2, IMC2):
	case FORMAT(IMC3, IMC3):
	case FORMAT(IMC4, IMC4):
	case FORMAT(YV12, YV12): fmt = ImageFormat::Lum; break;
	case FORMAT(UYVY, UYVY): fmt = ImageFormat::Lum, pixStride = 2, pixOffset = 1; break;
	case FORMAT(YUYV, YUYV): fmt = ImageFormat::Lum, pixStride = 2; break;

	case FORMAT(Y8, Y8): fmt = ImageFormat::Lum; break;
	case FORMAT(Y16, Y16): fmt = ImageFormat::Lum, pixStride = 2, pixOffset = 1; break;

#if (QT_VERSION >= QT_VERSION_CHECK(5, 13, 0))
	case FORMAT(ABGR32, ABGR8888):
#if Q_BYTE_ORDER == Q_LITTLE_ENDIAN
		fmt = ImageFormat::RGBX;
#else
		fmt = ImageFormat::XBGR;
#endif
		break;
#endif

#if (QT_VERSION >= QT_VERSION_CHECK(5, 14, 0))
	case FORMAT(YUV422P, YUV422P): fmt = ImageFormat::Lum; break;
#endif
	default: break;
	}

	if (fmt != ImageFormat::None) {
		auto img = frame; // shallow copy just get access to non-const map() function
#if QT_VERSION < QT_VERSION_CHECK(6, 0, 0)
		if (!img.isValid() || !img.map(QAbstractVideoBuffer::ReadOnly)){
#else
		if (!img.isValid() || !img.map(QVideoFrame::ReadOnly)){
#endif
			qWarning() << "invalid QVideoFrame: could not map memory";
			return {};
		}
		QScopeGuard unmap([&] { img.unmap(); });

		return QListResults(ZXing::ReadBarcodes(
			{img.bits(FIRST_PLANE) + pixOffset, img.width(), img.height(), fmt, img.bytesPerLine(FIRST_PLANE), pixStride}, opts));
	}
	else {
#if QT_VERSION < QT_VERSION_CHECK(6, 0, 0)
		if (QVideoFrame::imageFormatFromPixelFormat(frame.pixelFormat()) != QImage::Format_Invalid) {
			qWarning() << "unsupported QVideoFrame::pixelFormat";
			return {};
		}
		auto qimg = frame.image();
#else
		auto qimg = frame.toImage();
#endif
		if (qimg.format() != QImage::Format_Invalid)
			return ReadBarcodes(qimg, opts);
		qWarning() << "failed to convert QVideoFrame to QImage";
		return {};
	}
}

inline Result ReadBarcode(const QVideoFrame& frame, const ReaderOptions& opts = {})
{
	auto res = ReadBarcodes(frame, ReaderOptions(opts).setMaxNumberOfSymbols(1));
	return !res.isEmpty() ? res.takeFirst() : Result();
}

#define ZQ_PROPERTY(Type, name, setter) \
public: \
	Q_PROPERTY(Type name READ name WRITE setter NOTIFY name##Changed) \
	Type name() const noexcept { return ReaderOptions::name(); } \
	Q_SLOT void setter(const Type& newVal) \
	{ \
		if (name() != newVal) { \
			ReaderOptions::setter(newVal); \
			emit name##Changed(); \
		} \
	} \
	Q_SIGNAL void name##Changed();


#if QT_VERSION < QT_VERSION_CHECK(6, 0, 0)
class BarcodeReader : public QAbstractVideoFilter, private ReaderOptions
#else
class BarcodeReader : public QObject, private ReaderOptions
#endif
{
	Q_OBJECT

public:
#if QT_VERSION < QT_VERSION_CHECK(6, 0, 0)
	BarcodeReader(QObject* parent = nullptr) : QAbstractVideoFilter(parent), busy(false), sleepTime(200), cropRect(0, 0, 0, 0) {}
#else
	BarcodeReader(QObject* parent = nullptr) : QObject(parent) {}
#endif

	Q_PROPERTY(int formats READ formats WRITE setFormats NOTIFY formatsChanged)
	int formats() const noexcept
	{
		auto fmts = ReaderOptions::formats();
		return *reinterpret_cast<int*>(&fmts);
	}
	Q_SLOT void setFormats(int newVal)
	{
		if (formats() != newVal) {
			ReaderOptions::setFormats(static_cast<ZXing::BarcodeFormat>(newVal));
			emit formatsChanged();
		}
	}
	Q_SIGNAL void formatsChanged();

	ZQ_PROPERTY(bool, tryRotate, setTryRotate)
	ZQ_PROPERTY(bool, tryHarder, setTryHarder)
	ZQ_PROPERTY(bool, tryDownscale, setTryDownscale)

	bool busy;
	int sleepTime;
	QRect cropRect;

public slots:
	void process(const QVideoFrame& image)
	{
		if (busy) return;

		busy = true;

		// Disable ourselves for a bit -- we don't need to sample at full throttle
		setActive(false);
		QTimer::singleShot(sleepTime, this, [this] { setActive(true); });

		// Sadly have to grab the image data here because we need the GL context to be current

#if QT_VERSION < QT_VERSION_CHECK(6, 0, 0)
		QImage img = image.image();
#else
		QImage img = image.toImage();
#endif

		if (!cropRect.isNull()) {
			img = img.copy(cropRect);
		}

		QtConcurrent::run(this, &BarcodeReader::process_internal, img);
	}

	void process_internal(QImage &image)
	{
		Result res = ReadBarcode(image, *this);
		if (!cropRect.isNull()) {
			for (int i = 0; i < 4; i++) {
				res._position[i] += cropRect.topLeft();
			}
		}
		emit newResult(res);

		if (res.isValid()) {
			// We have a code! Sample more often and only around the area where we found the code
			// so the animation looks nice

			// Calculate a box that fits all 4 points, then pad it some
			cropRect.setRect(0, 0, 0, 0);

			QPoint topLeft = QPoint(INT_MAX, INT_MAX);
			QPoint bottomRight = QPoint(INT_MIN, INT_MIN);

			for (int i = 0; i < 4; i++) {
				QPoint p = res.position()[i];
				topLeft.setX(std::min(topLeft.x(), p.x()));
				topLeft.setY(std::min(topLeft.y(), p.y()));
				bottomRight.setX(std::max(bottomRight.x(), p.x()));
				bottomRight.setY(std::max(bottomRight.y(), p.y()));
			}

			cropRect.setTopLeft(topLeft);
			cropRect.setBottomRight(bottomRight);

			int w = std::max(500, std::min(cropRect.width() * 2, cropRect.width() + 200));
			int h = std::max(500, std::min(cropRect.height() * 2, cropRect.height() + 200));

			cropRect.moveTopLeft(cropRect.topLeft() - (QPoint(w, h) - QPoint(cropRect.width(), cropRect.height())) / 2);
			cropRect.setSize(QSize(w, h));

			// Wake from our slumber

			if (sleepTime != 20) {
				sleepTime = 20;
				setActive(true);
			}
		} else {
			sleepTime = 200;
			cropRect.setRect(0, 0, 0, 0);
		}

		busy = false;
	}

signals:
	void newResult(ZXingQt::Result result);

#if QT_VERSION < QT_VERSION_CHECK(6, 0, 0)
public:
	QVideoFilterRunnable *createFilterRunnable() override;
#else
private:
	QVideoSink *_sink = nullptr;

public:
	void setVideoSink(QVideoSink* sink) {
		if (_sink == sink)
			return;

		if (_sink)
			disconnect(_sink, nullptr, this, nullptr);

		_sink = sink;
		connect(_sink, &QVideoSink::videoFrameChanged, this, &BarcodeReader::process);
	}
	Q_PROPERTY(QVideoSink* videoSink WRITE setVideoSink)
#endif

};

#undef ZX_PROPERTY

#if QT_VERSION < QT_VERSION_CHECK(6, 0, 0)
class VideoFilterRunnable : public QVideoFilterRunnable
{
	BarcodeReader* _filter = nullptr;

public:
	explicit VideoFilterRunnable(BarcodeReader* filter) : _filter(filter) {}

	QVideoFrame run(QVideoFrame* input, const QVideoSurfaceFormat& /*surfaceFormat*/, RunFlags /*flags*/) override
	{
		_filter->process(*input);
		return *input;
	}
};

inline QVideoFilterRunnable* BarcodeReader::createFilterRunnable()
{
	return new VideoFilterRunnable(this);
}
#endif

} // namespace ZXingQt


Q_DECLARE_METATYPE(ZXingQt::Position)
Q_DECLARE_METATYPE(ZXingQt::Result)

namespace ZXingQt {

inline void registerQmlAndMetaTypes()
{
	qRegisterMetaType<ZXingQt::BarcodeFormat>("BarcodeFormat");
	qRegisterMetaType<ZXingQt::ContentType>("ContentType");

	// supposedly the Q_DECLARE_METATYPE should be used with the overload without a custom name
	// but then the qml side complains about "unregistered type"
	qRegisterMetaType<ZXingQt::Position>("Position");
	qRegisterMetaType<ZXingQt::Result>("Result");

	qmlRegisterUncreatableMetaObject(
		ZXingQt::staticMetaObject, "ZXing", 1, 0, "ZXing", "Access to enums & flags only");
	qmlRegisterType<ZXingQt::BarcodeReader>("ZXing", 1, 0, "BarcodeReader");
}

} // namespace ZXingQt
