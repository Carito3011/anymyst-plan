// Pantalla de un proyecto: tablero de etapas, escenas y resumen del avance.
import 'package:flutter/material.dart';

import 'almacen.dart';
import 'archivos.dart';
import 'calendario.dart';
import 'modelo.dart';
import 'tema.dart';

class PaginaProyecto extends StatefulWidget {
  final Almacen almacen;
  final Proyecto proyecto;
  const PaginaProyecto({super.key, required this.almacen, required this.proyecto});

  @override
  State<PaginaProyecto> createState() => _PaginaProyectoState();
}

class _PaginaProyectoState extends State<PaginaProyecto> {
  Proyecto get p => widget.proyecto;
  int _seccion = 0;
  final _cal = GlobalKey<CalendarioState>();

  Future<void> _guardar() async {
    await widget.almacen.guardar(p);
    if (mounted) setState(() {});
  }

  void _avisar(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // --- acciones

  Future<void> _importarGuion() async {
    try {
      final r = await Plataforma.abrir();
      if (r == null) return;
      final (nuevas, cambiadas, fuera) = sincronizarConGuion(p, r.$2);
      await _guardar();
      _avisar('Guion leído: $nuevas escenas nuevas, $cambiadas cambiadas'
          '${fuera > 0 ? ', $fuera ya no están en el guion' : ''}');
    } catch (e) {
      _avisar('No pude leer el guion: $e');
    }
  }

  Future<void> _exportar() async {
    try {
      final ok = await Plataforma.guardar(
          '${nombreArchivo(p.nombre)}.anmp', 'application/octet-stream', escribirAnmp(p));
      _avisar(ok ? 'Plan guardado (.anmp)' : 'Exportación cancelada');
    } catch (e) {
      _avisar('No pude exportar: $e');
    }
  }

  Future<void> _editarProyecto() async {
    final n = TextEditingController(text: p.nombre);
    final d = TextEditingController(text: p.director);
    final s = TextEditingController(text: p.descripcion);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Proyecto'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: n, decoration: const InputDecoration(labelText: 'Nombre de la película')),
            TextField(controller: d, decoration: const InputDecoration(labelText: 'Director o directora')),
            TextField(
                controller: s,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Descripción')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;
    p.nombre = n.text.trim().isEmpty ? p.nombre : n.text.trim();
    p.director = d.text.trim();
    p.descripcion = s.text.trim();
    await _guardar();
  }

  Future<void> _editarEscena(Escena? escena) async {
    final nueva = escena == null;
    final e = escena ?? Escena();
    final enc = TextEditingController(text: e.encabezado);
    final res = TextEditingController(text: e.resumen);
    final notas = TextEditingController(text: e.notas);
    final etapasTemp = Map<String, String>.of(e.etapas);
    final fechasTemp = Map<String, String>.of(e.fechas);
    final accion = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Tema.superficie,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.85,
            child: ListView(padding: const EdgeInsets.all(20), children: [
              Text(nueva ? 'Nueva escena' : 'Escena',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Tema.coral)),
              if (e.fueraDelGuion)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('⚠ Esta escena ya no está en el guion',
                      style: TextStyle(color: Tema.dorado)),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: enc,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                    labelText: 'Encabezado (ej. INT. COCINA - DÍA)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: res,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Resumen', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              const Text('Etapas', style: TextStyle(fontWeight: FontWeight.bold)),
              for (final et in etapas)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    SizedBox(
                      width: 110,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(et),
                        InkWell(
                          onTap: () async {
                            final actual = DateTime.tryParse(fechasTemp[et] ?? '');
                            final f = await showDatePicker(
                                context: ctx,
                                helpText: 'Entrega de $et',
                                initialDate: actual ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2040));
                            if (f != null) set(() => fechasTemp[et] = fechaTexto(f));
                          },
                          onLongPress: () => set(() => fechasTemp.remove(et)),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              fechasTemp[et] == null
                                  ? '+ fecha'
                                  : '📅 ${fechaBonita(DateTime.parse(fechasTemp[et]!))}',
                              style: const TextStyle(fontSize: 11, color: Tema.coral),
                            ),
                          ),
                        ),
                      ]),
                    ),
                    Expanded(
                      child: Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final (clave, nombre, _, color) in estados)
                          ChoiceChip(
                            label: Text(nombre, style: const TextStyle(fontSize: 12)),
                            selected: (etapasTemp[et] ?? 'pendiente') == clave,
                            selectedColor: Color(color).withValues(alpha: 0.6),
                            visualDensity: VisualDensity.compact,
                            onSelected: (_) => set(() => etapasTemp[et] = clave),
                          ),
                      ]),
                    ),
                  ]),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: notas,
                maxLines: 4,
                decoration: const InputDecoration(
                    labelText: 'Notas (pendientes, responsables, ideas…)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              Row(children: [
                if (!nueva)
                  TextButton.icon(
                    onPressed: () => Navigator.pop(ctx, 'borrar'),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Borrar escena'),
                  ),
                const Spacer(),
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                const SizedBox(width: 8),
                FilledButton(onPressed: () => Navigator.pop(ctx, 'guardar'), child: const Text('Guardar')),
              ]),
            ]),
          ),
        ),
      ),
    );
    if (accion == 'borrar') {
      p.escenas.remove(e);
    } else if (accion == 'guardar') {
      e
        ..encabezado = enc.text.trim().toUpperCase()
        ..resumen = res.text.trim()
        ..notas = notas.text.trim()
        ..etapas = etapasTemp
        ..fechas = fechasTemp;
      if (nueva) p.escenas.add(e);
    } else {
      return;
    }
    await _guardar();
  }

  void _cambiarEstado(Escena e, String etapa) {
    e.etapas[etapa] = siguienteEstado(e.estadoDe(etapa));
    _guardar();
  }

  // --- secciones

  Widget _barra(double v, {double alto = 6}) => ClipRRect(
        borderRadius: BorderRadius.circular(alto),
        child: LinearProgressIndicator(
          value: v,
          minHeight: alto,
          backgroundColor: Tema.superficieAlta,
          color: v >= 1 ? const Color(0xFF4FC38A) : Tema.coral,
        ),
      );

  Widget _vacio() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.movie_filter_outlined, size: 56, color: Tema.textoSuave),
            const SizedBox(height: 12),
            const Text('Todavía no hay escenas.',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('Importa el guion de Anymyst Script (.anms) o crea las escenas a mano.',
                textAlign: TextAlign.center, style: TextStyle(color: Tema.textoSuave)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _importarGuion,
              icon: const Icon(Icons.description),
              label: const Text('Importar guion (.anms)'),
            ),
            TextButton.icon(
              onPressed: () => _editarEscena(null),
              icon: const Icon(Icons.add),
              label: const Text('Crear escena'),
            ),
          ]),
        ),
      );

  /// Tablero: escenas en filas, etapas en columnas. Toca una casilla para cambiar su estado.
  Widget _tablero() {
    if (p.escenas.isEmpty) return _vacio();
    const anchoNombre = 230.0, anchoCelda = 92.0, alto = 52.0;
    Widget celda(Escena e, String et) {
      final (_, nombre, _, color) = estado(e.estadoDe(et));
      return InkWell(
        onTap: () => _cambiarEstado(e, et),
        child: Container(
          width: anchoCelda,
          height: alto,
          padding: const EdgeInsets.all(4),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Color(color).withValues(alpha: e.estadoDe(et) == 'pendiente' ? 0.5 : 0.85),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(nombre,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11,
                      color: e.estadoDe(et) == 'pendiente' ? Tema.textoSuave : const Color(0xFF15111C),
                      fontWeight: FontWeight.w600)),
              if (e.fechaDe(et) != null)
                Builder(builder: (_) {
                  final f = soloDia(e.fechaDe(et)!);
                  final ent = Entrega(f, escena: e, etapa: et);
                  return Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                        color: colorAlerta(ent.alerta), borderRadius: BorderRadius.circular(4)),
                    child: Text('${f.day}/${f.month}',
                        style: const TextStyle(fontSize: 9, color: Color(0xFF15111C))),
                  );
                }),
            ]),
          ),
        ),
      );
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: Row(children: [
          const Expanded(
            child: Text('Toca una casilla para avanzar su estado.',
                style: TextStyle(color: Tema.textoSuave, fontSize: 13)),
          ),
          for (final (_, nombre, _, color) in estados) ...[
            Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: Color(color), borderRadius: BorderRadius.circular(3))),
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 10),
              child: Text(nombre, style: const TextStyle(fontSize: 12)),
            ),
          ],
        ]),
      ),
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: anchoNombre + anchoCelda * etapas.length + 16,
            child: Column(children: [
              Row(children: [
                const SizedBox(width: anchoNombre + 8, child: Padding(
                  padding: EdgeInsets.only(left: 16),
                  child: Text('Escena', style: TextStyle(fontWeight: FontWeight.bold)),
                )),
                for (final et in etapas)
                  SizedBox(
                    width: anchoCelda,
                    child: Column(children: [
                      Text(et,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: _barra(p.avanceEtapa(et), alto: 4),
                      ),
                    ]),
                  ),
              ]),
              const Divider(color: Tema.borde),
              Expanded(
                child: ListView.builder(
                  itemCount: p.escenas.length,
                  itemBuilder: (_, i) {
                    final e = p.escenas[i];
                    return Row(children: [
                      SizedBox(
                        width: anchoNombre + 8,
                        child: InkWell(
                          onTap: () => _editarEscena(e),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(
                                '${i + 1}. ${e.encabezado.isEmpty ? '(sin encabezado)' : e.encabezado}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: e.fueraDelGuion ? Tema.dorado : null),
                              ),
                              const SizedBox(height: 4),
                              Row(children: [
                                Expanded(child: _barra(e.avance, alto: 4)),
                                const SizedBox(width: 6),
                                Text(porcentaje(e.avance),
                                    style: const TextStyle(fontSize: 11, color: Tema.textoSuave)),
                              ]),
                            ]),
                          ),
                        ),
                      ),
                      for (final et in etapas) celda(e, et),
                    ]);
                  },
                ),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }

  Widget _escenas() {
    if (p.escenas.isEmpty) return _vacio();
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      itemCount: p.escenas.length,
      onReorder: (a, b) {
        if (b > a) b--;
        final e = p.escenas.removeAt(a);
        p.escenas.insert(b, e);
        _guardar();
      },
      itemBuilder: (_, i) {
        final e = p.escenas[i];
        final enCurso = etapas.where((et) => e.estadoDe(et) != 'pendiente' && e.estadoDe(et) != 'hecho');
        return Card(
          key: ValueKey(e.id),
          child: ListTile(
            onTap: () => _editarEscena(e),
            leading: CircleAvatar(
              backgroundColor: Tema.superficieAlta,
              child: Text('${i + 1}', style: const TextStyle(color: Tema.coral, fontWeight: FontWeight.bold)),
            ),
            title: Text(e.encabezado.isEmpty ? '(sin encabezado)' : e.encabezado,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 6),
              _barra(e.avance),
              const SizedBox(height: 4),
              Text([
                porcentaje(e.avance),
                if (enCurso.isNotEmpty) 'En curso: ${enCurso.join(', ')}',
                if (e.fueraDelGuion) '⚠ Ya no está en el guion',
              ].join(' · ')),
            ]),
          ),
        );
      },
    );
  }

  Widget _resumen() {
    final total = p.avance;
    final terminadas = p.escenas.where((e) => e.avance >= 1).length;
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text(p.nombre, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      if (p.director.isNotEmpty)
        Text('Dirección: ${p.director}', style: const TextStyle(color: Tema.textoSuave)),
      if (p.descripcion.isNotEmpty)
        Padding(padding: const EdgeInsets.only(top: 8), child: Text(p.descripcion)),
      const SizedBox(height: 24),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(porcentaje(total),
            style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Tema.coral)),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text('de la película\n$terminadas de ${p.escenas.length} escenas terminadas',
              style: const TextStyle(color: Tema.textoSuave)),
        ),
      ]),
      const SizedBox(height: 8),
      _barra(total, alto: 12),
      const SizedBox(height: 28),
      const Text('Avance por etapa', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      const SizedBox(height: 8),
      for (final et in etapas)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            SizedBox(width: 110, child: Text(et)),
            Expanded(child: _barra(p.avanceEtapa(et), alto: 10)),
            SizedBox(
                width: 56,
                child: Text(porcentaje(p.avanceEtapa(et)), textAlign: TextAlign.right)),
          ]),
        ),
    ]);
  }

  static const _secciones = [
    (Icons.grid_view_outlined, Icons.grid_view, 'Tablero'),
    (Icons.view_list_outlined, Icons.view_list, 'Escenas'),
    (Icons.calendar_month_outlined, Icons.calendar_month, 'Calendario'),
    (Icons.insights_outlined, Icons.insights, 'Resumen'),
  ];

  @override
  Widget build(BuildContext context) {
    final ancha = MediaQuery.sizeOf(context).width >= 900;
    final cuerpo = IndexedStack(index: _seccion, children: [
      _tablero(),
      _escenas(),
      Calendario(key: _cal, proyecto: p, alCambiar: _guardar, abrirEscena: _editarEscena),
      _resumen(),
    ]);
    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: _editarProyecto,
          child: Text(p.nombre.toUpperCase(), overflow: TextOverflow.ellipsis),
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('${p.escenas.length} escenas · ${porcentaje(p.avance)}',
                  style: const TextStyle(color: Tema.textoSuave, fontSize: 13)),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'guion':
                  _importarGuion();
                  break;
                case 'exportar':
                  _exportar();
                  break;
                case 'proyecto':
                  _editarProyecto();
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'guion',
                  child: ListTile(
                      leading: Icon(Icons.description),
                      title: Text('Importar o actualizar desde el guion (.anms)'))),
              PopupMenuItem(
                  value: 'exportar',
                  child: ListTile(leading: Icon(Icons.ios_share), title: Text('Exportar plan (.anmp)'))),
              PopupMenuItem(
                  value: 'proyecto',
                  child: ListTile(leading: Icon(Icons.edit_note), title: Text('Datos del proyecto'))),
            ],
          ),
        ],
      ),
      floatingActionButton: _seccion == 3
          ? null
          : _seccion == 2
              ? FloatingActionButton.extended(
                  onPressed: () => _cal.currentState?.editarHito(),
                  icon: const Icon(Icons.flag),
                  label: const Text('Hito'),
                )
              : FloatingActionButton.extended(
              onPressed: () => _editarEscena(null),
              icon: const Icon(Icons.add),
              label: const Text('Escena'),
            ),
      bottomNavigationBar: ancha
          ? null
          : NavigationBar(
              selectedIndex: _seccion,
              onDestinationSelected: (i) => setState(() => _seccion = i),
              destinations: [
                for (final (a, b, t) in _secciones)
                  NavigationDestination(icon: Icon(a), selectedIcon: Icon(b), label: t),
              ],
            ),
      body: ancha
          ? Row(children: [
              NavigationRail(
                selectedIndex: _seccion,
                onDestinationSelected: (i) => setState(() => _seccion = i),
                labelType: NavigationRailLabelType.all,
                destinations: [
                  for (final (a, b, t) in _secciones)
                    NavigationRailDestination(icon: Icon(a), selectedIcon: Icon(b), label: Text(t)),
                ],
              ),
              const VerticalDivider(width: 1, color: Tema.borde),
              Expanded(child: cuerpo),
            ])
          : cuerpo,
    );
  }
}
