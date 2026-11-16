// ZIP mínimo: escribe sin compresión y lee archivos guardados o comprimidos (deflate).
import 'dart:io';
import 'dart:typed_data';

class EntradaZip {
  final String nombre;
  final Uint8List datos;
  EntradaZip(this.nombre, this.datos);
}

final Uint32List _tabla = () {
  final t = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
    }
    t[n] = c;
  }
  return t;
}();

int crc32(List<int> datos) {
  var c = 0xFFFFFFFF;
  for (final b in datos) {
    c = _tabla[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

Uint8List crearZip(List<EntradaZip> entradas) {
  final salida = BytesBuilder();
  final central = BytesBuilder();
  final offsets = <int>[];
  final crcs = <int>[];

  for (final e in entradas) {
    final nombre = Uint8List.fromList(e.nombre.codeUnits);
    final crc = crc32(e.datos);
    crcs.add(crc);
    offsets.add(salida.length);
    final h = ByteData(30);
    h.setUint32(0, 0x04034b50, Endian.little);
    h.setUint16(4, 20, Endian.little);
    h.setUint16(6, 0, Endian.little);
    h.setUint16(8, 0, Endian.little); // sin compresión
    h.setUint16(10, 0, Endian.little);
    h.setUint16(12, 0x21, Endian.little);
    h.setUint32(14, crc, Endian.little);
    h.setUint32(18, e.datos.length, Endian.little);
    h.setUint32(22, e.datos.length, Endian.little);
    h.setUint16(26, nombre.length, Endian.little);
    h.setUint16(28, 0, Endian.little);
    salida.add(h.buffer.asUint8List());
    salida.add(nombre);
    salida.add(e.datos);
  }

  final inicioCentral = salida.length;
  for (var i = 0; i < entradas.length; i++) {
    final e = entradas[i];
    final nombre = Uint8List.fromList(e.nombre.codeUnits);
    final c = ByteData(46);
    c.setUint32(0, 0x02014b50, Endian.little);
    c.setUint16(4, 20, Endian.little);
    c.setUint16(6, 20, Endian.little);
    c.setUint16(8, 0, Endian.little);
    c.setUint16(10, 0, Endian.little);
    c.setUint16(12, 0, Endian.little);
    c.setUint16(14, 0x21, Endian.little);
    c.setUint32(16, crcs[i], Endian.little);
    c.setUint32(20, e.datos.length, Endian.little);
    c.setUint32(24, e.datos.length, Endian.little);
    c.setUint16(28, nombre.length, Endian.little);
    c.setUint16(30, 0, Endian.little);
    c.setUint16(32, 0, Endian.little);
    c.setUint16(34, 0, Endian.little);
    c.setUint16(36, 0, Endian.little);
    c.setUint32(38, 0, Endian.little);
    c.setUint32(42, offsets[i], Endian.little);
    central.add(c.buffer.asUint8List());
    central.add(nombre);
  }
  final datosCentral = central.toBytes();
  salida.add(datosCentral);

  final fin = ByteData(22);
  fin.setUint32(0, 0x06054b50, Endian.little);
  fin.setUint16(4, 0, Endian.little);
  fin.setUint16(6, 0, Endian.little);
  fin.setUint16(8, entradas.length, Endian.little);
  fin.setUint16(10, entradas.length, Endian.little);
  fin.setUint32(12, datosCentral.length, Endian.little);
  fin.setUint32(16, inicioCentral, Endian.little);
  fin.setUint16(20, 0, Endian.little);
  salida.add(fin.buffer.asUint8List());
  return salida.toBytes();
}

/// Lee un ZIP. Lanza FormatException si no lo es.
Map<String, Uint8List> leerZip(Uint8List bytes) {
  final d = ByteData.sublistView(bytes);
  var fin = -1;
  for (var i = bytes.length - 22; i >= 0 && i >= bytes.length - 66000; i--) {
    if (d.getUint32(i, Endian.little) == 0x06054b50) {
      fin = i;
      break;
    }
  }
  if (fin < 0) throw const FormatException('No es un archivo ZIP');
  final total = d.getUint16(fin + 10, Endian.little);
  var p = d.getUint32(fin + 16, Endian.little);
  final r = <String, Uint8List>{};
  for (var n = 0; n < total; n++) {
    if (d.getUint32(p, Endian.little) != 0x02014b50) break;
    final metodo = d.getUint16(p + 10, Endian.little);
    final tamComp = d.getUint32(p + 20, Endian.little);
    final largoNombre = d.getUint16(p + 28, Endian.little);
    final largoExtra = d.getUint16(p + 30, Endian.little);
    final largoComent = d.getUint16(p + 32, Endian.little);
    final local = d.getUint32(p + 42, Endian.little);
    final nombre = String.fromCharCodes(
        bytes.sublist(p + 46, p + 46 + largoNombre));
    final lNombre = d.getUint16(local + 26, Endian.little);
    final lExtra = d.getUint16(local + 28, Endian.little);
    final inicio = local + 30 + lNombre + lExtra;
    final comp = bytes.sublist(inicio, inicio + tamComp);
    if (metodo == 0) {
      r[nombre] = Uint8List.fromList(comp);
    } else if (metodo == 8) {
      r[nombre] = Uint8List.fromList(ZLibDecoder(raw: true).convert(comp));
    }
    p += 46 + largoNombre + largoExtra + largoComent;
  }
  return r;
}
