// Guardado en la tablet y puente con Android (guardar / abrir archivos).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'modelo.dart';

class Plataforma {
  static const _canal = MethodChannel('anymyst/archivos');

  static Future<String> carpetaDatos() async {
    try {
      final r = await _canal.invokeMethod<String>('carpetaDatos');
      if (r != null) return r;
    } on MissingPluginException {
      // fuera de Android
    }
    return Directory.systemTemp.path;
  }

  static Future<bool> guardar(String nombre, String mime, Uint8List bytes) async {
    final r = await _canal.invokeMethod<bool>(
        'guardar', {'nombre': nombre, 'mime': mime, 'bytes': bytes});
    return r ?? false;
  }

  static void Function(String, Uint8List)? alRecibir;

  static void iniciar() {
    _canal.setMethodCallHandler((c) async {
      if (c.method == 'recibido') {
        final m = c.arguments as Map;
        alRecibir?.call(m['nombre'].toString(), m['bytes'] as Uint8List);
      }
      return null;
    });
  }

  /// Archivo que Anymyst Script mandó al abrir Plan.
  static Future<(String, Uint8List)?> archivoRecibido() async {
    try {
      final r = await _canal.invokeMethod<Map<dynamic, dynamic>>('archivoRecibido');
      if (r == null) return null;
      return (r['nombre'].toString(), r['bytes'] as Uint8List);
    } on MissingPluginException {
      return null;
    }
  }

  static Future<(String, String)?> elegirCarpeta() async {
    final r = await _canal.invokeMethod<Map<dynamic, dynamic>>('elegirCarpeta');
    if (r == null) return null;
    return (r['uri'].toString(), r['nombre'].toString());
  }

  /// (nombre, fecha) de los archivos de la carpeta.
  static Future<List<(String, DateTime)>> listarCarpeta(String carpeta) async {
    final r = await _canal.invokeMethod<List<dynamic>>('listarCarpeta', {'carpeta': carpeta}) ?? [];
    return [
      for (final x in r)
        ((x as Map)['nombre'].toString(),
            DateTime.fromMillisecondsSinceEpoch((x['fecha'] as num?)?.toInt() ?? 0))
    ];
  }

  static Future<Uint8List?> leerDeCarpeta(String carpeta, String nombre) =>
      _canal.invokeMethod<Uint8List>('leerDeCarpeta', {'carpeta': carpeta, 'nombre': nombre});

  static Future<void> escribirEnCarpeta(String carpeta, String nombre, Uint8List bytes) =>
      _canal.invokeMethod('escribirEnCarpeta', {'carpeta': carpeta, 'nombre': nombre, 'bytes': bytes});

  static Future<(String, Uint8List)?> abrir() async {
    final r = await _canal.invokeMethod<Map<dynamic, dynamic>>('abrir');
    if (r == null) return null;
    return (r['nombre'].toString(), r['bytes'] as Uint8List);
  }
}

class Almacen {
  late Directory _dir;
  String carpetaUri = '';
  String carpetaNombre = '';

  Future<void> iniciar() async {
    final base = await Plataforma.carpetaDatos();
    _dir = Directory('$base/proyectos');
    await _dir.create(recursive: true);
    try {
      final f = File('$base/ajustes.json');
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map;
        carpetaUri = (j['carpetaUri'] ?? '').toString();
        carpetaNombre = (j['carpetaNombre'] ?? '').toString();
      }
    } catch (_) {}
  }

  Future<void> guardarAjustes() async {
    await File('${_dir.parent.path}/ajustes.json').writeAsString(
        jsonEncode({'carpetaUri': carpetaUri, 'carpetaNombre': carpetaNombre}));
  }

  Future<List<Proyecto>> listar() async {
    final r = <Proyecto>[];
    await for (final f in _dir.list()) {
      if (f is File && f.path.endsWith('.json')) {
        try {
          r.add(Proyecto.fromJson(
              Map<String, dynamic>.from(jsonDecode(await f.readAsString()) as Map)));
        } catch (_) {}
      }
    }
    r.sort((a, b) => b.modificado.compareTo(a.modificado));
    return r;
  }

  Future<void> guardar(Proyecto p) async {
    p.modificado = DateTime.now();
    final tmp = File('${_dir.path}/${p.id}.tmp');
    await tmp.writeAsString(jsonEncode(p.toJson()), flush: true);
    await tmp.rename('${_dir.path}/${p.id}.json');
  }

  Future<void> borrar(Proyecto p) async {
    final f = File('${_dir.path}/${p.id}.json');
    if (await f.exists()) await f.delete();
  }
}
