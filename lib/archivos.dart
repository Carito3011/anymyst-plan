// Importar escenas desde Anymyst Script (.anms) y exportar/importar el plan (.anmp).
import 'dart:convert';
import 'dart:typed_data';

import 'modelo.dart';
import 'zip.dart';

const mimeAnmp = 'application/x-anymyst-plan';

/// Lee un .anms: (id del guion, título, escenas).
(String, String, List<Escena>) leerGuion(Uint8List bytes) {
  final archivos = leerZip(bytes);
  final json = archivos['anymyst.json'];
  if (json == null) throw const FormatException('No es un guion de Anymyst Script');
  final g = Map<String, dynamic>.from(jsonDecode(utf8.decode(json)) as Map);
  final escenas = <Escena>[];
  final actos = <String, String>{
    for (final a in (g['actos'] as List?) ?? [])
      (a as Map)['id'].toString(): (a['nombre'] ?? '').toString()
  };
  Escena? actual;
  var lineas = 0.0;
  void sumarDuracion() {
    // Una página (~54 líneas) es más o menos un minuto de película
    final e = actual;
    if (e != null) e.segundos = (lineas * 60 / 54).round();
    lineas = 0;
  }
  final texto = StringBuffer();
  void cerrar() {
    final e = actual;
    if (e != null && e.resumen.isEmpty) {
      final t = texto.toString().trim();
      e.resumen = t.length > 300 ? '${t.substring(0, 300)}…' : t;
    }
    texto.clear();
  }

  for (final b in (g['bloques'] as List?) ?? []) {
    final m = Map<String, dynamic>.from(b as Map);
    final tipo = (m['tipo'] ?? '').toString();
    final t = (m['texto'] ?? '').toString().trim();
    final largo = t.length;
    switch (tipo) {
      case 'escena':
        lineas += 2;
      case 'accion':
        lineas += 1 + (largo / 60).ceil();
      case 'personaje':
        lineas += 1;
      case 'parentesis':
        lineas += 1;
      case 'dialogo':
        lineas += (largo / 35).ceil();
      default:
        lineas += 1;
    }
    if (tipo == 'escena') {
      lineas -= 2;
      sumarDuracion();
      lineas = 2;
      cerrar();
      final nueva = Escena(
        idGuion: (m['id'] ?? '').toString(),
        encabezado: t.toUpperCase(),
        resumen: (m['nota'] ?? '').toString(),
        acto: actos[(m['acto'] ?? '').toString()] ?? '',
      );
      // Si el guion ya lo tiene escrito, la etapa Guion empieza como hecha
      if (t.isNotEmpty) nueva.etapas['Guion'] = 'hecho';
      actual = nueva;
      escenas.add(nueva);
    } else if (actual != null && t.isNotEmpty && tipo == 'accion') {
      texto.write('$t ');
    }
  }
  sumarDuracion();
  cerrar();
  return ((g['id'] ?? '').toString(), (g['titulo'] ?? '').toString(), escenas);
}

/// Pone las escenas del guion en el proyecto sin perder el avance.
/// Devuelve (nuevas, actualizadas, fuera del guion).
(int, int, int) sincronizarConGuion(Proyecto p, Uint8List bytes) {
  final (guionId, titulo, nuevas) = leerGuion(bytes);
  final viejas = List<Escena>.of(p.escenas);
  final usadas = <Escena>{};
  final resultado = <Escena>[];
  var nn = 0, act = 0;
  String normal(String s) => s.toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  for (final n in nuevas) {
    Escena? previa;
    for (final v in viejas) {
      if (!usadas.contains(v) && v.idGuion.isNotEmpty && v.idGuion == n.idGuion) {
        previa = v;
        break;
      }
    }
    if (previa == null) {
      for (final v in viejas) {
        if (!usadas.contains(v) && v.idGuion.isEmpty && normal(v.encabezado) == normal(n.encabezado)) {
          previa = v;
          break;
        }
      }
    }
    if (previa != null) {
      usadas.add(previa);
      if (previa.encabezado != n.encabezado) act++;
      previa
        ..encabezado = n.encabezado
        ..resumen = n.resumen.isNotEmpty ? n.resumen : previa.resumen
        ..idGuion = n.idGuion
        ..acto = n.acto
        ..segundos = n.segundos
        ..fueraDelGuion = false;
      resultado.add(previa);
    } else {
      nn++;
      resultado.add(n);
    }
  }
  var fuera = 0;
  for (final v in viejas) {
    if (usadas.contains(v)) continue;
    final conAvance = v.etapas.values.any((e) => e != 'pendiente' && e.isNotEmpty);
    if (!conAvance && v.idGuion.isNotEmpty) continue;
    v.fueraDelGuion = true;
    fuera++;
    resultado.add(v);
  }
  p.escenas = resultado;
  p.guionId = guionId;
  if ((p.nombre.trim().isEmpty || p.nombre == 'Sin título') && titulo.isNotEmpty) {
    p.nombre = titulo;
  }
  return (nn, act, fuera);
}

Uint8List escribirAnmp(Proyecto p) => crearZip([
      EntradaZip('mimetype', Uint8List.fromList(utf8.encode(mimeAnmp))),
      EntradaZip('anymyst-plan.json',
          Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent(' ').convert(p.toJson())))),
      EntradaZip(
          'LEEME.txt',
          Uint8List.fromList(utf8.encode('Archivo de Anymyst Plan (.anmp)\n'
              '- anymyst-plan.json: proyecto, escenas y estado de cada etapa\n'))),
    ]);

Proyecto leerAnmp(Uint8List bytes) {
  final json = leerZip(bytes)['anymyst-plan.json'];
  if (json == null) throw const FormatException('No es un archivo .anmp');
  final p = Proyecto.fromJson(Map<String, dynamic>.from(jsonDecode(utf8.decode(json)) as Map));
  p.id = nuevoId();
  return p;
}

/// Id del guion dentro de un .anms ('' si no se puede leer).
String idDeGuion(Uint8List bytes) {
  try {
    final json = leerZip(bytes)['anymyst.json'];
    if (json == null) return '';
    return ((jsonDecode(utf8.decode(json)) as Map)['id'] ?? '').toString();
  } catch (_) {
    return '';
  }
}

/// Lee un storyboard de Anymyst Board (.anmb) y marca la etapa Storyboard.
/// Una escena con viñetas pasa a "En curso"; si todas sus viñetas tienen dibujo, a "Hecho".
/// Nunca baja una etapa que ya estaba más avanzada. Devuelve (guionId, escenas actualizadas).
(String, int) aplicarStoryboard(Proyecto p, Uint8List bytes) {
  final json = leerZip(bytes)['anymyst-board.json'];
  if (json == null) throw const FormatException('No es un storyboard de Anymyst Board');
  final t = Map<String, dynamic>.from(jsonDecode(utf8.decode(json)) as Map);
  String normal(String s) => s.toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  const orden = ['pendiente', 'curso', 'revision', 'hecho'];
  var n = 0;
  for (final eb in (t['escenas'] as List?) ?? []) {
    final m = Map<String, dynamic>.from(eb as Map);
    final idGuion = (m['idGuion'] ?? '').toString();
    final enc = normal((m['encabezado'] ?? '').toString());
    Escena? e;
    for (final x in p.escenas) {
      if ((idGuion.isNotEmpty && x.idGuion == idGuion) || (enc.isNotEmpty && normal(x.encabezado) == enc)) {
        e = x;
        break;
      }
    }
    if (e == null) continue;
    final vinetas = (m['vinetas'] as List?) ?? [];
    if (vinetas.isEmpty) continue;
    var conDibujo = 0;
    for (final v in vinetas) {
      final vm = v as Map;
      final dibujada = vm['fondo'] == true ||
          ((vm['capas'] as List?) ?? []).any((c) => (((c as Map)['trazos'] as List?) ?? []).isNotEmpty);
      if (dibujada) conDibujo++;
    }
    if (conDibujo == 0) continue;
    final nuevo = conDibujo == vinetas.length ? 'hecho' : 'curso';
    final actual = e.estadoDe('Storyboard');
    if (orden.indexOf(nuevo) > orden.indexOf(actual)) {
      e.ponerEstado('Storyboard', nuevo);
      n++;
    }
  }
  return ((t['guionId'] ?? '').toString(), n);
}

String idDeStoryboard(Uint8List bytes) {
  try {
    final json = leerZip(bytes)['anymyst-board.json'];
    if (json == null) return '';
    return ((jsonDecode(utf8.decode(json)) as Map)['guionId'] ?? '').toString();
  } catch (_) {
    return '';
  }
}

/// Avance que deja Anymyst Studio (<película>_studio.json) en la carpeta compartida.
/// Sube las etapas que Studio marcó más avanzadas; nunca baja lo que pusiste aquí.
/// Devuelve (id del guion, etapas cambiadas) o null si no es un avance de Studio.
(String, int)? aplicarAvanceStudio(Proyecto p, Uint8List bytes) {
  Map<String, dynamic> t;
  try {
    t = Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
  } catch (_) {
    return null;
  }
  if (t['formato'] != 'anymyst-studio-avance') return null;
  final guionId = (t['guion_id'] ?? '').toString();
  if (p.guionId.isNotEmpty && guionId.isNotEmpty && guionId != p.guionId) return (guionId, 0);
  String normal(String s) => s.toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  const orden = ['pendiente', 'curso', 'revision', 'hecho'];
  var n = 0;
  for (final es in (t['escenas'] as List?) ?? []) {
    final m = Map<String, dynamic>.from(es as Map);
    final idGuion = (m['idGuion'] ?? '').toString();
    final enc = normal((m['encabezado'] ?? '').toString());
    Escena? e;
    for (final x in p.escenas) {
      if ((idGuion.isNotEmpty && x.idGuion == idGuion) || (idGuion.isEmpty && enc.isNotEmpty && normal(x.encabezado) == enc)) {
        e = x;
        break;
      }
    }
    if (e == null) continue;
    final et = Map<String, dynamic>.from((m['etapas'] as Map?) ?? {});
    for (final etapa in etapas) {
      final nuevo = (et[etapa] ?? '').toString();
      if (!orden.contains(nuevo)) continue;
      if (orden.indexOf(nuevo) > orden.indexOf(e.estadoDe(etapa))) {
        e.ponerEstado(etapa, nuevo);
        n++;
      }
    }
  }
  return (guionId, n);
}
