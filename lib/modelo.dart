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

class Escena {
  String id;
  String idGuion; // id de la escena en Anymyst Script ('' si se creó aquí)
  String encabezado;
  String resumen;
  String notas;
  bool fueraDelGuion;
  Map<String, String> etapas; // etapa -> estado

  Escena({
    String? id,
    this.idGuion = '',
    this.encabezado = '',
    this.resumen = '',
    this.notas = '',
    this.fueraDelGuion = false,
    Map<String, String>? etapas,
  })  : id = id ?? nuevoId(),
        etapas = etapas ?? {};

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
      );
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
  DateTime creado;
  DateTime modificado;

  Proyecto({
    String? id,
    required this.nombre,
    this.director = '',
    this.descripcion = '',
    this.guionId = '',
    List<Escena>? escenas,
    DateTime? creado,
    DateTime? modificado,
  })  : id = id ?? nuevoId(),
        escenas = escenas ?? [],
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
      };

  static Proyecto fromJson(Map<String, dynamic> j) => Proyecto(
        id: j['id']?.toString(),
        nombre: (j['nombre'] ?? 'Sin título').toString(),
        director: (j['director'] ?? '').toString(),
        descripcion: (j['descripcion'] ?? '').toString(),
        guionId: (j['guionId'] ?? '').toString(),
        escenas: ((j['escenas'] as List?) ?? [])
            .map((e) => Escena.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
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
