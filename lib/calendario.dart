// Calendario de producción: entregas por escena y etapa, hitos, vista de mes y semana.
import 'package:flutter/material.dart';

import 'modelo.dart';
import 'tema.dart';

const colorAtrasado = Color(0xFFE5534B);
const colorPronto = Color(0xFFE8B84A);
const colorATiempo = Color(0xFF7A8CFF);
const colorHecho = Color(0xFF4FC38A);

Color colorAlerta(int a) => switch (a) {
      -1 => colorAtrasado,
      0 => colorPronto,
      2 => colorHecho,
      _ => colorATiempo,
    };

class Calendario extends StatefulWidget {
  final Proyecto proyecto;
  final VoidCallback alCambiar;
  final void Function(Escena) abrirEscena;
  const Calendario(
      {super.key, required this.proyecto, required this.alCambiar, required this.abrirEscena});

  @override
  State<Calendario> createState() => CalendarioState();
}

class CalendarioState extends State<Calendario> {
  Proyecto get p => widget.proyecto;
  bool _mes = true;
  DateTime _referencia = soloDia(DateTime.now());
  DateTime _elegido = soloDia(DateTime.now());

  Map<DateTime, List<Entrega>> _porDia(List<Entrega> todas) {
    final r = <DateTime, List<Entrega>>{};
    for (final e in todas) {
      r.putIfAbsent(e.fecha, () => []).add(e);
    }
    return r;
  }

  Future<void> editarHito([Hito? hito]) async {
    final nombre = TextEditingController(text: hito?.nombre ?? '');
    var fecha = DateTime.tryParse(hito?.fecha ?? '') ?? _elegido;
    final accion = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(hito == null ? 'Nuevo hito' : 'Hito'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: nombre,
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: 'Nombre (ej. Fin del storyboard, Festival, Estreno)'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final f = await showDatePicker(
                      context: ctx,
                      initialDate: fecha,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2040));
                  if (f != null) set(() => fecha = f);
                },
                icon: const Icon(Icons.event),
                label: Text(fechaBonita(fecha) + ' de ${fecha.year}'),
              ),
            ]),
          ),
          actions: [
            if (hito != null)
              TextButton(onPressed: () => Navigator.pop(ctx, 'borrar'), child: const Text('Borrar')),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'guardar'), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (accion == 'borrar' && hito != null) {
      p.hitos.remove(hito);
    } else if (accion == 'guardar' && nombre.text.trim().isNotEmpty) {
      if (hito == null) {
        p.hitos.add(Hito(nombre: nombre.text.trim(), fecha: fechaTexto(fecha)));
      } else {
        hito
          ..nombre = nombre.text.trim()
          ..fecha = fechaTexto(fecha);
      }
    } else {
      return;
    }
    widget.alCambiar();
    setState(() {});
  }

  void _abrir(Entrega e) {
    if (e.hito != null) {
      editarHito(e.hito);
    } else if (e.escena != null) {
      widget.abrirEscena(e.escena!);
    }
  }

  Widget _fila(Entrega e, {bool conFecha = false}) {
    final c = colorAlerta(e.alerta);
    return Card(
      child: ListTile(
        dense: true,
        onTap: () => _abrir(e),
        leading: Container(
            width: 10,
            height: 36,
            decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4))),
        title: Text(e.titulo,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                decoration: e.hecha ? TextDecoration.lineThrough : null)),
        subtitle: Text([
          if (conFecha) fechaBonita(e.fecha),
          if (e.escena != null && e.escena!.encabezado.isNotEmpty) e.escena!.encabezado,
          if (e.escena != null) estado(e.escena!.estadoDe(e.etapa)).$2,
          if (e.alerta == -1) 'ATRASADO',
        ].join(' · ')),
      ),
    );
  }

  Widget _mesVista(Map<DateTime, List<Entrega>> porDia) {
    final primero = DateTime(_referencia.year, _referencia.month, 1);
    final inicio = primero.subtract(Duration(days: primero.weekday - 1));
    final hoy = soloDia(DateTime.now());
    return Column(children: [
      Row(children: [for (final d in diasCortos) Expanded(child: Center(child: Text(d, style: const TextStyle(color: Tema.textoSuave, fontSize: 12))))]),
      const SizedBox(height: 4),
      for (var semana = 0; semana < 6; semana++)
        Row(children: [
          for (var d = 0; d < 7; d++)
            Builder(builder: (_) {
              final dia = DateTime(inicio.year, inicio.month, inicio.day + semana * 7 + d);
              final items = porDia[dia] ?? [];
              final delMes = dia.month == _referencia.month;
              final elegido = dia == _elegido;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _elegido = dia),
                  child: Container(
                    height: 54,
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: elegido ? Tema.superficieAlta : Tema.superficie,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: dia == hoy ? Tema.coral : (elegido ? Tema.borde : Colors.transparent),
                          width: dia == hoy ? 2 : 1),
                    ),
                    child: Column(children: [
                      const SizedBox(height: 4),
                      Text('${dia.day}',
                          style: TextStyle(
                              fontSize: 13,
                              color: delMes ? Tema.texto : Tema.textoSuave.withValues(alpha: 0.5),
                              fontWeight: dia == hoy ? FontWeight.bold : null)),
                      const SizedBox(height: 4),
                      Wrap(spacing: 3, children: [
                        for (final e in items.take(4))
                          Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                  color: e.hito != null ? Tema.dorado : colorAlerta(e.alerta),
                                  shape: e.hito != null ? BoxShape.rectangle : BoxShape.circle)),
                      ]),
                      if (items.length > 4)
                        Text('+${items.length - 4}', style: const TextStyle(fontSize: 9, color: Tema.textoSuave)),
                    ]),
                  ),
                ),
              );
            }),
        ]),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: Text(fechaBonita(_elegido),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
      const SizedBox(height: 6),
      if ((porDia[_elegido] ?? []).isEmpty)
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text('Nada para este día.', style: TextStyle(color: Tema.textoSuave)),
        ),
      for (final e in porDia[_elegido] ?? <Entrega>[]) _fila(e),
    ]);
  }

  Widget _semanaVista(Map<DateTime, List<Entrega>> porDia) {
    final inicio = _referencia.subtract(Duration(days: _referencia.weekday - 1));
    final hoy = soloDia(DateTime.now());
    return Column(children: [
      for (var d = 0; d < 7; d++)
        Builder(builder: (_) {
          final dia = DateTime(inicio.year, inicio.month, inicio.day + d);
          final items = porDia[dia] ?? [];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${diasCortos[d]} ${fechaBonita(dia)}${dia == hoy ? ' · hoy' : ''}',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: dia == hoy ? Tema.coral : Tema.texto)),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('—', style: TextStyle(color: Tema.textoSuave)),
                ),
              for (final e in items) _fila(e),
            ]),
          );
        }),
    ]);
  }

  void _mover(int paso) => setState(() {
        if (_mes) {
          _referencia = DateTime(_referencia.year, _referencia.month + paso, 1);
        } else {
          _referencia = _referencia.add(Duration(days: 7 * paso));
        }
      });

  @override
  Widget build(BuildContext context) {
    final todas = p.entregas();
    final porDia = _porDia(todas);
    final atrasadas = todas.where((e) => e.alerta == -1).toList();
    final pronto = todas.where((e) => e.alerta == 0).toList();
    final inicioSemana = _referencia.subtract(Duration(days: _referencia.weekday - 1));
    final titulo = _mes
        ? '${meses[_referencia.month - 1][0].toUpperCase()}${meses[_referencia.month - 1].substring(1)} ${_referencia.year}'
        : 'Semana del ${fechaBonita(inicioSemana)}';
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
      if (atrasadas.isNotEmpty)
        Card(
          color: colorAtrasado.withValues(alpha: 0.18),
          child: ExpansionTile(
            leading: const Icon(Icons.warning_amber, color: colorAtrasado),
            title: Text('${atrasadas.length} entregas atrasadas',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            children: [for (final e in atrasadas) _fila(e, conFecha: true)],
          ),
        ),
      if (pronto.isNotEmpty)
        Card(
          color: colorPronto.withValues(alpha: 0.14),
          child: ExpansionTile(
            leading: const Icon(Icons.schedule, color: colorPronto),
            title: Text('${pronto.length} vencen en los próximos 3 días',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            children: [for (final e in pronto) _fila(e, conFecha: true)],
          ),
        ),
      const SizedBox(height: 8),
      Row(children: [
        IconButton(onPressed: () => _mover(-1), icon: const Icon(Icons.chevron_left)),
        Expanded(
          child: Text(titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        IconButton(onPressed: () => _mover(1), icon: const Icon(Icons.chevron_right)),
      ]),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Mes'), icon: Icon(Icons.calendar_month)),
            ButtonSegment(value: false, label: Text('Semana'), icon: Icon(Icons.view_week)),
          ],
          selected: {_mes},
          onSelectionChanged: (s) => setState(() => _mes = s.first),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: () => setState(() {
            _referencia = soloDia(DateTime.now());
            _elegido = _referencia;
          }),
          child: const Text('Hoy'),
        ),
      ]),
      const SizedBox(height: 12),
      _mes ? _mesVista(porDia) : _semanaVista(porDia),
      const SizedBox(height: 16),
      Wrap(spacing: 14, runSpacing: 6, children: [
        for (final (c, t) in [
          (colorAtrasado, 'Atrasado'),
          (colorPronto, 'Vence pronto'),
          (colorATiempo, 'A tiempo'),
          (colorHecho, 'Hecho'),
          (Tema.dorado, 'Hito'),
        ])
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Text(t, style: const TextStyle(fontSize: 12, color: Tema.textoSuave)),
          ]),
      ]),
      if (todas.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 16),
          child: Text(
            'Pon fechas de entrega abriendo una escena (cada etapa tiene su fecha) o crea hitos con el botón "Hito".',
            style: TextStyle(color: Tema.textoSuave),
          ),
        ),
    ]);
  }
}
