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

  static Future<(String, Uint8List)?> abrir() async {
    final r = await _canal.invokeMethod<Map<dynamic, dynamic>>('abrir');
    if (r == null) return null;
    return (r['nombre'].toString(), r['bytes'] as Uint8List);
  }
}

class Almacen {
  late Directory _dir;

  Future<void> iniciar() async {
    final base = await Plataforma.carpetaDatos();
    _dir = Directory('$base/proyectos');
    await _dir.create(recursive: true);
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
