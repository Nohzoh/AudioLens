import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiolens/services/exif_location_service.dart';

/// Builds a minimal JPEG (SOI + APP1 EXIF + EOI) carrying GPS tags.
///
/// TIFF layout (little-endian):
///  0x00 "II*" + offset 8 -> IFD0 (GPS IFD pointer)
///  0x08 IFD0: 1 entry (tag 0x8825 -> GPS IFD at offset 26)
///  0x1A GPS IFD: 5 entries (GPSVersionID, LatRef, Lat, LonRef, Lon)
///  0x5C 6 RATIONALs (lat deg/min/sec, lon deg/min/sec)
Uint8List buildJpegWithExifGps({
  required int latDeg,
  required int latMin,
  required int latSecNum,
  required int latSecDen,
  required int lonDeg,
  required int lonMin,
  required int lonSecNum,
  required int lonSecDen,
  required String latRef,
  required String lonRef,
}) {
  const rationalsOffset = 92;
  const tiffSize = 140;
  final tiff = ByteData(tiffSize);
  tiff.setUint8(0, 0x49); // 'I'
  tiff.setUint8(1, 0x49); // 'I'
  tiff.setUint16(2, 42, Endian.little);
  tiff.setUint32(4, 8, Endian.little); // offset to IFD0
  // IFD0
  tiff.setUint16(8, 1, Endian.little);
  tiff.setUint16(10, 0x8825, Endian.little); // GPS IFD pointer tag
  tiff.setUint16(12, 4, Endian.little); // type LONG
  tiff.setUint32(14, 1, Endian.little);
  tiff.setUint32(18, 26, Endian.little); // GPS IFD offset
  tiff.setUint32(22, 0, Endian.little); // next IFD
  // GPS IFD
  int o = 26;
  tiff.setUint16(o, 5, Endian.little);
  o += 2;
  void entry(int tag, int type, int count, Uint8List value4) {
    tiff.setUint16(o, tag, Endian.little);
    tiff.setUint16(o + 2, type, Endian.little);
    tiff.setUint32(o + 4, count, Endian.little);
    for (var i = 0; i < 4; i++) {
      tiff.setUint8(o + 8 + i, i < value4.length ? value4[i] : 0);
    }
    o += 12;
  }

  entry(0x0000, 1, 4, Uint8List.fromList([2, 0, 0, 0])); // GPSVersionID
  entry(0x0001, 2, 2, Uint8List.fromList([latRef.codeUnitAt(0), 0]));
  final latOffset = ByteData(4)..setUint32(0, rationalsOffset, Endian.little);
  entry(0x0002, 5, 3, latOffset.buffer.asUint8List()); // GPSLatitude
  entry(0x0003, 2, 2, Uint8List.fromList([lonRef.codeUnitAt(0), 0]));
  final lonOffset = ByteData(4)
    ..setUint32(0, rationalsOffset + 24, Endian.little);
  entry(0x0004, 5, 3, lonOffset.buffer.asUint8List()); // GPSLongitude
  tiff.setUint32(o, 0, Endian.little); // next IFD
  // RATIONALs
  void rational(int offset, int num, int den) {
    tiff.setUint32(offset, num, Endian.little);
    tiff.setUint32(offset + 4, den, Endian.little);
  }

  rational(rationalsOffset, latDeg, 1);
  rational(rationalsOffset + 8, latMin, 1);
  rational(rationalsOffset + 16, latSecNum, latSecDen);
  rational(rationalsOffset + 24, lonDeg, 1);
  rational(rationalsOffset + 32, lonMin, 1);
  rational(rationalsOffset + 40, lonSecNum, lonSecDen);
  // Wrap in JPEG with APP1 "Exif\0\0"
  final exifPayload = Uint8List(6 + tiffSize);
  exifPayload.setRange(0, 4, 'Exif'.codeUnits);
  exifPayload[4] = 0;
  exifPayload[5] = 0;
  exifPayload.setRange(6, 6 + tiffSize, tiff.buffer.asUint8List());
  final app1Length = 2 + exifPayload.length;
  final total = 2 + 2 + app1Length + 2;
  final jpeg = ByteData(total);
  jpeg.setUint8(0, 0xFF);
  jpeg.setUint8(1, 0xD8); // SOI
  jpeg.setUint8(2, 0xFF);
  jpeg.setUint8(3, 0xE1); // APP1
  jpeg.setUint16(4, app1Length, Endian.big);
  for (var i = 0; i < exifPayload.length; i++) {
    jpeg.setUint8(6 + i, exifPayload[i]);
  }
  final eoi = total - 2;
  jpeg.setUint8(eoi, 0xFF);
  jpeg.setUint8(eoi + 1, 0xD9); // EOI
  return jpeg.buffer.asUint8List();
}

void main() {
  test('readGpsFromImage parses N/E coordinates', () async {
    final dir = Directory.systemTemp.createTempSync('exif-gps-ne');
    final file = File('${dir.path}/gps.jpg');
    file.writeAsBytesSync(buildJpegWithExifGps(
      latDeg: 45,
      latMin: 30,
      latSecNum: 0,
      latSecDen: 1,
      lonDeg: 4,
      lonMin: 50,
      lonSecNum: 0,
      lonSecDen: 1,
      latRef: 'N',
      lonRef: 'E',
    ));

    final coords = await ExifLocationService.readGpsFromImage(file);

    expect(coords, isNotNull);
    expect(coords!.lat, closeTo(45.5, 0.0001));
    expect(coords.lon, closeTo(4.8333, 0.0001));
    dir.deleteSync(recursive: true);
  });

  test('readGpsFromImage applies S/W sign to coordinates', () async {
    final dir = Directory.systemTemp.createTempSync('exif-gps-sw');
    final file = File('${dir.path}/gps.jpg');
    file.writeAsBytesSync(buildJpegWithExifGps(
      latDeg: 45,
      latMin: 30,
      latSecNum: 0,
      latSecDen: 1,
      lonDeg: 4,
      lonMin: 50,
      lonSecNum: 0,
      lonSecDen: 1,
      latRef: 'S',
      lonRef: 'W',
    ));

    final coords = await ExifLocationService.readGpsFromImage(file);

    expect(coords, isNotNull);
    expect(coords!.lat, closeTo(-45.5, 0.0001));
    expect(coords.lon, closeTo(-4.8333, 0.0001));
    dir.deleteSync(recursive: true);
  });

  test('readGpsFromImage returns null for image without GPS tags', () async {
    final dir = Directory.systemTemp.createTempSync('exif-gps-none');
    final file = File('${dir.path}/plain.jpg');
    file.writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);

    final coords = await ExifLocationService.readGpsFromImage(file);

    expect(coords, isNull);
    dir.deleteSync(recursive: true);
  });
}
