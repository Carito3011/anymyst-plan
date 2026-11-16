// Modelo de Anymyst Plan: proyecto (la película) -> escenas -> etapas con estado.
import 'dart:math';

int _contador = 0;
String nuevoId() =>
    '${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(9999)}${_contador++}';

/// Etapas de producción, en orden.
const etapas = [
  'Guion',
  'Storyboard',
  'Layout',
  'Modelado',
  'Rig',
  'Animación',
  'Voces',
  'Render',
  'Edición',
  'Sonido',
];

/// Estados de una etapa: (clave, nombre, avance 0..1, color ARGB).
const estados = [
  ('pendiente', 'Pendiente', 0.0, 0xFF3A3346),
  ('curso', 'En curso', 0.5, 0xFFE8B84A),
  ('revision', 'En revisión', 0.8, 0xFF7A8CFF),
  ('hecho', 'Hecho', 1.0, 0xFF4FC38A),
];

(String, String, double, int) estado(String clave) =>
    estados.firstWhere((e) => e.$1 == clave, orElse: () => estados.first);

String siguienteEstado(String clave) {
  final i = estados.indexWhere((e) => e.$1 == clave);
  return estados[(i + 1) % estados.length].$1;
}

/// Tarea de la checklist de una etapa.
class Tarea {
  String texto;
  bool hecha;
  Tarea(this.texto, {this.hecha = false});
  Map<String, dynamic> toJson() => {'t': texto, if (hecha) 'h': true};
  static Tarea fromJson(Map<String, dynamic> j) => Tarea((j['t'] ?? '').toString(), hecha: j['h'] == true);
}

class Escena {
  String id;
  String idGuion; // id de la escena en Anymyst Script ('' si se creó aquí)
  String encabezado;
  String resumen;
  String notas;
  bool fueraDelGuion;
  Map<String, String> etapas; // etapa -> estado
  Map<String, String> fechas; // etapa -> fecha de entrega 'AAAA-MM-DD'
  Map<String, String> hechoEn; // etapa -> día en que se marcó Hecho
  Map<String, List<Tarea>> tareas; // etapa -> checklist
  int segundos; // duración; -1 = desconocida
  String acto;

  Escena({
    String? id,
    this.idGuion = '',
    this.encabezado = '',
    this.resumen = '',
    this.notas = '',
    this.fueraDelGuion = false,
    Map<String, String>? etapas,
    Map<String, String>? fechas,
    Map<String, String>? hechoEn,
    Map<String, List<Tarea>>? tareas,
    this.segundos = -1,
    this.acto = '',
  })  : id = id ?? nuevoId(),
        etapas = etapas ?? {},
        fechas = fechas ?? {},
        hechoEn = hechoEn ?? {},
        tareas = tareas ?? {};

  /// Cambia el estado y recuerda cuándo se terminó (para medir el ritmo).
  void ponerEstado(String etapa, String nuevo) {
    final antes = estadoDe(etapa);
    etapas[etapa] = nuevo;
    if (nuevo == 'hecho' && antes != 'hecho') {
      hechoEn[etapa] = fechaTexto(DateTime.now());
    } else if (nuevo != 'hecho') {
      hechoEn.remove(etapa);
    }
  }

  int get etapasHechas => etapasPlan.where((e) => estadoDe(e) == 'hecho').length;

  /// "Guion ✓ · Storyboard ✓ · 2 de 10 etapas"
  String get resumenEtapas {
    final hechas = etapasPlan.where((e) => estadoDe(e) == 'hecho').toList();
    final nombres = hechas.length <= 3 ? hechas.map((e) => '$e ✓').join(' · ') : '';
    return [if (nombres.isNotEmpty) nombres, '${hechas.length} de ${etapasPlan.length} etapas'].join(' · ');
  }

  DateTime? fechaDe(String etapa) => DateTime.tryParse(fechas[etapa] ?? '');

  String estadoDe(String etapa) => etapas[etapa] ?? 'pendiente';

  double get avance =>
      etapasPlan.fold(0.0, (s, e) => s + estado(estadoDe(e)).$3) / etapasPlan.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        if (idGuion.isNotEmpty) 'idGuion': idGuion,
        'encabezado': encabezado,
        'resumen': resumen,
        'notas': notas,
        if (fueraDelGuion) 'fueraDelGuion': true,
        'etapas': etapas,
        if (fechas.isNotEmpty) 'fechas': fechas,
        if (hechoEn.isNotEmpty) 'hechoEn': hechoEn,
        if (tareas.isNotEmpty)
          'tareas': tareas.map((k, v) => MapEntry(k, v.map((t) => t.toJson()).toList())),
        if (segundos >= 0) 'segundos': segundos,
        if (acto.isNotEmpty) 'acto': acto,
      };

  static Escena fromJson(Map<String, dynamic> j) => Escena(
        id: j['id']?.toString(),
        idGuion: (j['idGuion'] ?? '').toString(),
        encabezado: (j['encabezado'] ?? '').toString(),
        resumen: (j['resumen'] ?? '').toString(),
        notas: (j['notas'] ?? '').toString(),
        fueraDelGuion: j['fueraDelGuion'] == true,
        etapas: (j['etapas'] is Map)
            ? (j['etapas'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()))
            : null,
        fechas: (j['fechas'] is Map)
            ? (j['fechas'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()))
            : null,
        hechoEn: (j['hechoEn'] is Map)
            ? (j['hechoEn'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()))
            : null,
        tareas: (j['tareas'] is Map)
            ? (j['tareas'] as Map).map((k, v) => MapEntry(
                k.toString(),
                ((v as List?) ?? [])
                    .map((t) => Tarea.fromJson(Map<String, dynamic>.from(t as Map)))
                    .toList()))
            : null,
        segundos: (j['segundos'] as num?)?.toInt() ?? -1,
        acto: (j['acto'] ?? '').toString(),
      );
}

/// Hito de la película (fin del storyboard, festival, estreno…).
class Hito {
  String id;
  String nombre;
  String fecha; // 'AAAA-MM-DD'
  Hito({String? id, required this.nombre, required this.fecha}) : id = id ?? nuevoId();
  Map<String, dynamic> toJson() => {'id': id, 'nombre': nombre, 'fecha': fecha};
  static Hito fromJson(Map<String, dynamic> j) => Hito(
      id: j['id']?.toString(),
      nombre: (j['nombre'] ?? 'Hito').toString(),
      fecha: (j['fecha'] ?? '').toString());
}

String fechaTexto(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime soloDia(DateTime d) => DateTime(d.year, d.month, d.day);

const meses = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
];
const diasCortos = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

String fechaBonita(DateTime d) => '${d.day} de ${meses[d.month - 1]}';

/// Una entrega en el calendario.
class Entrega {
  final DateTime fecha;
  final Escena? escena;
  final int numero; // número de escena (0 si es hito)
  final String etapa;
  final Hito? hito;
  Entrega(this.fecha, {this.escena, this.numero = 0, this.etapa = '', this.hito});
  bool get hecha => escena != null && escena!.estadoDe(etapa) == 'hecho';
  /// -1 atrasada, 0 vence en 3 días o menos, 1 a tiempo, 2 hecha
  int get alerta {
    if (hecha) return 2;
    final hoy = soloDia(DateTime.now());
    if (fecha.isBefore(hoy)) return hito == null ? -1 : 1;
    if (fecha.difference(hoy).inDays <= 3) return 0;
    return 1;
  }
  String get titulo => hito != null ? '★ ${hito!.nombre}' : 'Escena $numero · $etapa';
}

/// Alias para no confundir la lista global con el mapa de cada escena.
const etapasPlan = etapas;

class Proyecto {
  String id;
  String nombre;
  String director;
  String descripcion;
  String guionId;
  List<Escena> escenas;
  List<Hito> hitos;
  String fechaMeta; // estreno o fecha de entrega final 'AAAA-MM-DD'
  DateTime creado;
  DateTime modificado;

  Proyecto({
    String? id,
    required this.nombre,
    this.director = '',
    this.descripcion = '',
    this.guionId = '',
    List<Escena>? escenas,
    List<Hito>? hitos,
    this.fechaMeta = '',
    DateTime? creado,
    DateTime? modificado,
  })  : id = id ?? nuevoId(),
        escenas = escenas ?? [],
        hitos = hitos ?? [],
        creado = creado ?? DateTime.now(),
        modificado = modificado ?? DateTime.now();

  double get avance => escenas.isEmpty
      ? 0
      : escenas.fold(0.0, (s, e) => s + e.avance) / escenas.length;

  /// Avance de una etapa en toda la película (0..1).
  double avanceEtapa(String etapa) => escenas.isEmpty
      ? 0
      : escenas.fold(0.0, (s, e) => s + estado(e.estadoDe(etapa)).$3) / escenas.length;

  Map<String, dynamic> toJson() => {
        'formato_archivo': 1,
        'id': id,
        'nombre': nombre,
        'director': director,
        'descripcion': descripcion,
        if (guionId.isNotEmpty) 'guionId': guionId,
        'creado': creado.toIso8601String(),
        'modificado': modificado.toIso8601String(),
        'escenas': escenas.map((e) => e.toJson()).toList(),
        'hitos': hitos.map((h) => h.toJson()).toList(),
        if (fechaMeta.isNotEmpty) 'fechaMeta': fechaMeta,
      };

  // --- tiempo y ritmo

  int get segundosTotales => escenas.fold(0, (s, e) => s + (e.segundos > 0 ? e.segundos : 0));

  /// Segundos de película ponderados por avance.
  double get segundosAvanzados =>
      escenas.fold(0.0, (s, e) => s + (e.segundos > 0 ? e.segundos * e.avance : 0));

  int get segundosTerminados =>
      escenas.fold(0, (s, e) => s + (e.avance >= 1 && e.segundos > 0 ? e.segundos : 0));

  /// Etapas que faltan (en unidades de etapa completa).
  double get etapasFaltantes =>
      escenas.fold(0.0, (s, e) => s + (1 - e.avance) * etapasPlan.length);

  /// Etapas terminadas por semana, según las últimas 4 semanas.
  double get ritmoSemanal {
    final limite = soloDia(DateTime.now()).subtract(const Duration(days: 28));
    var n = 0;
    for (final e in escenas) {
      for (final f in e.hechoEn.values) {
        final d = DateTime.tryParse(f);
        if (d != null && !d.isBefore(limite)) n++;
      }
    }
    return n / 4;
  }

  /// Fecha estimada de fin al ritmo actual (null si no hay ritmo).
  DateTime? get finEstimado {
    final r = ritmoSemanal;
    if (r <= 0) return null;
    final semanas = etapasFaltantes / r;
    return soloDia(DateTime.now()).add(Duration(days: (semanas * 7).ceil()));
  }

  /// Etapas por semana necesarias para llegar a la fecha meta.
  double? get ritmoNecesario {
    final meta = DateTime.tryParse(fechaMeta);
    if (meta == null) return null;
    final dias = meta.difference(soloDia(DateTime.now())).inDays;
    if (dias <= 0) return null;
    return etapasFaltantes / (dias / 7);
  }

  /// Todas las fechas de entrega y los hitos, ordenados.
  List<Entrega> entregas() {
    final r = <Entrega>[];
    for (var i = 0; i < escenas.length; i++) {
      final e = escenas[i];
      for (final et in etapasPlan) {
        final f = e.fechaDe(et);
        if (f != null) r.add(Entrega(soloDia(f), escena: e, numero: i + 1, etapa: et));
      }
    }
    for (final h in hitos) {
      final f = DateTime.tryParse(h.fecha);
      if (f != null) r.add(Entrega(soloDia(f), hito: h));
    }
    r.sort((a, b) => a.fecha.compareTo(b.fecha));
    return r;
  }

  static Proyecto fromJson(Map<String, dynamic> j) => Proyecto(
        id: j['id']?.toString(),
        nombre: (j['nombre'] ?? 'Sin título').toString(),
        director: (j['director'] ?? '').toString(),
        descripcion: (j['descripcion'] ?? '').toString(),
        guionId: (j['guionId'] ?? '').toString(),
        escenas: ((j['escenas'] as List?) ?? [])
            .map((e) => Escena.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        hitos: ((j['hitos'] as List?) ?? [])
            .map((e) => Hito.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        fechaMeta: (j['fechaMeta'] ?? '').toString(),
        creado: DateTime.tryParse((j['creado'] ?? '').toString()),
        modificado: DateTime.tryParse((j['modificado'] ?? '').toString()),
      );
}

String porcentaje(double v) => '${(v * 100).round()} %';

String nombreArchivo(String titulo) {
  const mapa = {
    'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n',
    'Á': 'A', 'É': 'E', 'Í': 'I', 'Ó': 'O', 'Ú': 'U', 'Ü': 'U', 'Ñ': 'N',
  };
  final sb = StringBuffer();
  for (final c in titulo.trim().split('')) {
    sb.write(mapa[c] ?? c);
  }
  final t = sb
      .toString()
      .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), '_');
  return t.isEmpty ? 'plan' : t;
}

String duracionTexto(int segundos) {
  if (segundos <= 0) return '—';
  final m = segundos ~/ 60, s = segundos % 60;
  return m > 0 ? '$m min ${s.toString().padLeft(2, '0')} s' : '$s s';
}
