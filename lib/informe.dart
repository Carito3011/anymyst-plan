// Informe del avance en PDF (hecho a mano, sin paquetes): resumen + tabla de escenas.
import 'dart:convert';
import 'dart:typed_data';

import 'modelo.dart';

const _ancho = 792.0, _alto = 612.0; // carta horizontal

/// Texto PDF en WinAnsi: tildes y ñ funcionan; lo demás se cambia por algo parecido.
List<int> _texto(String s) {
  const cambios = {'✓': 'v', '★': '*', '·': '·', '…': '...', '—': '-', '–': '-', '“': '"', '”': '"', '’': "'"};
  final r = <int>[];
  for (final ch in s.split('')) {
    final c = cambios[ch] ?? ch;
    for (final u in c.runes) {
      final b = u < 256 ? u : 63; // '?'
      if (b == 40 || b == 41 || b == 92) r.add(92); // ( ) \
      r.add(b);
    }
  }
  return r;
}

class _Pagina {
  final List<int> c = [];
  void cmd(String s) => c.addAll(latin1.encode('$s\n'));
  void color(int argb) {
    final r = ((argb >> 16) & 255) / 255, g = ((argb >> 8) & 255) / 255, b = (argb & 255) / 255;
    cmd('${r.toStringAsFixed(3)} ${g.toStringAsFixed(3)} ${b.toStringAsFixed(3)} rg');
  }

  void rect(double x, double y, double w, double h, int argb) {
    color(argb);
    cmd('${x.toStringAsFixed(1)} ${(_alto - y - h).toStringAsFixed(1)} ${w.toStringAsFixed(1)} ${h.toStringAsFixed(1)} re f');
  }

  /// y = distancia desde arriba hasta la línea base.
  void texto(String s, double x, double y, double tam, {bool negrita = false, int argb = 0xFF1A1A1A}) {
    color(argb);
    c.addAll(latin1.encode('BT /${negrita ? 'F2' : 'F1'} ${tam.toStringAsFixed(1)} Tf '
        '${x.toStringAsFixed(1)} ${(_alto - y).toStringAsFixed(1)} Td ('));
    c.addAll(_texto(s));
    c.addAll(latin1.encode(') Tj ET\n'));
  }
}

String _corto(String s, int n) => s.length <= n ? s : '${s.substring(0, n - 1)}…';

Uint8List escribirInforme(Proyecto p) {
  final paginas = <_Pagina>[];
  final hoy = DateTime.now();
  const coral = 0xFFFF8A5B, gris = 0xFF6B6B6B, fondoBarra = 0xFFE6E6E6;

  // --- página 1: resumen
  final a = _Pagina();
  paginas.add(a);
  a.texto(p.nombre, 40, 60, 26, negrita: true);
  a.texto([
    if (p.director.isNotEmpty) 'Dirección: ${p.director}',
    'Informe del ${fechaBonita(hoy)} de ${hoy.year}',
  ].join('   ·   '), 40, 82, 11, argb: gris);
  if (p.descripcion.isNotEmpty) a.texto(_corto(p.descripcion, 120), 40, 100, 10, argb: gris);
  a.texto(porcentaje(p.avance), 40, 160, 48, negrita: true, argb: coral);
  a.texto('de la película', 40, 178, 11, argb: gris);
  a.rect(40, 188, 300, 10, fondoBarra);
  a.rect(40, 188, 300 * p.avance, 10, coral);

  final terminadas = p.escenas.where((e) => e.avance >= 1).length;
  final fin = p.finEstimado;
  final meta = DateTime.tryParse(p.fechaMeta);
  final datos = [
    ('Escenas', '${p.escenas.length} ($terminadas terminadas)'),
    ('Duración del guion', duracionTexto(p.segundosTotales)),
    ('Película terminada', duracionTexto(p.segundosTerminados)),
    ('Ritmo', '${p.ritmoSemanal.toStringAsFixed(1)} etapas por semana'),
    ('Fin estimado', fin == null ? 'sin datos de ritmo' : '${fechaBonita(fin)} de ${fin.year}'),
    if (meta != null) ('Fecha meta', '${fechaBonita(meta)} de ${meta.year}'),
    if (p.ritmoNecesario != null)
      ('Necesario para la meta', '${p.ritmoNecesario!.toStringAsFixed(1)} etapas por semana'),
  ];
  var y = 230.0;
  for (final (k, v) in datos) {
    a.texto(k, 40, y, 10, argb: gris);
    a.texto(v, 170, y, 10, negrita: true);
    y += 18;
  }

  a.texto('Avance por etapa', 420, 140, 13, negrita: true);
  y = 165;
  for (final et in etapas) {
    final v = p.avanceEtapa(et);
    a.texto(et, 420, y + 8, 10);
    a.rect(510, y, 200, 10, fondoBarra);
    a.rect(510, y, 200 * v, 10, v >= 1 ? 0xFF4FC38A : coral);
    a.texto(porcentaje(v), 718, y + 8, 9, argb: gris);
    y += 22;
  }

  final proximas = p.entregas().where((e) => !e.hecha && e.hito == null).take(8).toList();
  final hitos = p.hitos.toList()..sort((x, z) => x.fecha.compareTo(z.fecha));
  y = 420;
  if (proximas.isNotEmpty) {
    a.texto('Próximas entregas', 40, y, 13, negrita: true);
    y += 18;
    for (final e in proximas) {
      a.texto('${fechaBonita(e.fecha)}  ·  ${e.titulo}${e.alerta == -1 ? '  (ATRASADA)' : ''}', 40, y, 10,
          argb: e.alerta == -1 ? 0xFFC0392B : 0xFF1A1A1A);
      y += 15;
    }
  }
  if (hitos.isNotEmpty) {
    var yh = 420.0;
    a.texto('Hitos', 420, yh, 13, negrita: true);
    yh += 18;
    for (final h in hitos.take(8)) {
      final f = DateTime.tryParse(h.fecha);
      a.texto('${f == null ? h.fecha : '${fechaBonita(f)} ${f.year}'}  ·  ${h.nombre}', 420, yh, 10);
      yh += 15;
    }
  }

  // --- páginas de escenas
  const filasPorPagina = 24, celda = 30.0, x0 = 330.0;
  for (var i = 0; i < p.escenas.length; i += filasPorPagina) {
    final pg = _Pagina();
    paginas.add(pg);
    pg.texto('${p.nombre} — escenas', 40, 40, 14, negrita: true);
    pg.texto('N°', 40, 70, 9, negrita: true);
    pg.texto('Escena', 64, 70, 9, negrita: true);
    pg.texto('Avance', 280, 70, 9, negrita: true);
    for (var k = 0; k < etapas.length; k++) {
      pg.texto(_corto(etapas[k], 6), x0 + k * celda + 2, 70, 7, negrita: true);
    }
    var yy = 80.0;
    for (var j = i; j < p.escenas.length && j < i + filasPorPagina; j++) {
      final e = p.escenas[j];
      if ((j - i).isOdd) pg.rect(36, yy, _ancho - 72, 20, 0xFFF4F4F4);
      pg.texto('${j + 1}', 40, yy + 14, 9);
      pg.texto(_corto(e.encabezado.isEmpty ? '(sin encabezado)' : e.encabezado, 40), 64, yy + 14, 9);
      pg.texto(porcentaje(e.avance), 280, yy + 14, 9, negrita: true);
      for (var k = 0; k < etapas.length; k++) {
        final (_, _, _, color) = estado(e.estadoDe(etapas[k]));
        pg.rect(x0 + k * celda + 2, yy + 4, celda - 6, 12,
            e.estadoDe(etapas[k]) == 'pendiente' ? 0xFFDDDDDD : color);
      }
      yy += 20;
    }
    // leyenda
    var xl = 40.0;
    for (final (clave, nombre, _, color) in estados) {
      pg.rect(xl, _alto - 40, 10, 10, clave == 'pendiente' ? 0xFFDDDDDD : color);
      pg.texto(nombre, xl + 14, _alto - 31, 9);
      xl += 100;
    }
  }

  // --- armar el PDF
  final out = BytesBuilder();
  final offsets = <int>[];
  void obj(String cuerpo, [List<int>? flujo]) {
    offsets.add(out.length);
    out.add(latin1.encode('${offsets.length} 0 obj\n'));
    if (flujo == null) {
      out.add(latin1.encode('$cuerpo\nendobj\n'));
    } else {
      out.add(latin1.encode('<< /Length ${flujo.length} >>\nstream\n'));
      out.add(flujo);
      out.add(latin1.encode('\nendstream\nendobj\n'));
    }
  }

  out.add(latin1.encode('%PDF-1.4\n'));
  final n = paginas.length;
  // 1 catálogo, 2 páginas, 3-4 fuentes, luego (página, contenido) por cada una
  final kids = [for (var i = 0; i < n; i++) '${5 + i * 2} 0 R'].join(' ');
  obj('<< /Type /Catalog /Pages 2 0 R >>');
  obj('<< /Type /Pages /Kids [$kids] /Count $n >>');
  obj('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>');
  obj('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>');
  for (var i = 0; i < n; i++) {
    obj('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${_ancho.toInt()} ${_alto.toInt()}] '
        '/Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents ${6 + i * 2} 0 R >>');
    obj('', paginas[i].c);
  }
  final xref = out.length;
  final sb = StringBuffer('xref\n0 ${offsets.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    sb.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  sb.write('trailer\n<< /Size ${offsets.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  out.add(latin1.encode(sb.toString()));
  return out.toBytes();
}
