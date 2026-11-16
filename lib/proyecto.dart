// Pantalla de un proyecto: tablero de etapas, escenas y resumen del avance.
import 'package:flutter/material.dart';

import 'almacen.dart';
import 'archivos.dart';
import 'calendario.dart';
import 'informe.dart';
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
  String _filtro = 'todas'; // todas | pendientes | atrasadas | <etapa>

  /// Escenas que pasan el filtro, con su número original.
  List<(int, Escena)> _visibles() {
    final hoy = soloDia(DateTime.now());
    final r = <(int, Escena)>[];
    for (var i = 0; i < p.escenas.length; i++) {
      final e = p.escenas[i];
      final ok = switch (_filtro) {
        'todas' => true,
        'pendientes' => e.avance < 1,
        'atrasadas' => etapas.any((et) {
            final f = e.fechaDe(et);
            return f != null && e.estadoDe(et) != 'hecho' && soloDia(f).isBefore(hoy);
          }),
        _ => e.estadoDe(_filtro) != 'hecho',
      };
      if (ok) r.add((i + 1, e));
    }
    return r;
  }

  Widget _selectorFiltro() => DropdownButton<String>(
        value: _filtro,
        underline: const SizedBox(),
        items: [
          const DropdownMenuItem(value: 'todas', child: Text('Todas las escenas')),
          const DropdownMenuItem(value: 'pendientes', child: Text('Sin terminar')),
          const DropdownMenuItem(value: 'atrasadas', child: Text('Con entregas atrasadas')),
          for (final et in etapas) DropdownMenuItem(value: et, child: Text('Falta $et')),
        ],
        onChanged: (v) => setState(() => _filtro = v ?? 'todas'),
      );

  Future<void> _marcarTodas(String etapa) async {
    final visibles = _visibles();
    final nuevo = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('$etapa en ${visibles.length} escenas'
            '${_filtro == 'todas' ? '' : ' (las del filtro)'}'),
        children: [
          for (final (clave, nombre, _, color) in estados)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, clave),
              child: Row(children: [
                Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(color: Color(color), borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 10),
                Text('Marcar como $nombre'),
              ]),
            ),
        ],
      ),
    );
    if (nuevo == null) return;
    for (final (_, e) in visibles) {
      e.ponerEstado(etapa, nuevo);
    }
    await _guardar();
  }

  Future<void> _editarTareas(String etapa, List<Tarea> lista, void Function(void Function()) set) async {
    final nueva = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set2) => AlertDialog(
          title: Text('Checklist de $etapa'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final t in List<Tarea>.of(lista))
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: t.hecha,
                  title: Text(t.texto),
                  secondary: IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => set2(() => lista.remove(t)),
                  ),
                  onChanged: (v) => set2(() => t.hecha = v ?? false),
                ),
              TextField(
                controller: nueva,
                decoration: const InputDecoration(hintText: 'Nueva tarea (ej. Personaje David)'),
                onSubmitted: (x) => set2(() {
                  if (x.trim().isNotEmpty) lista.add(Tarea(x.trim()));
                  nueva.clear();
                }),
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (nueva.text.trim().isNotEmpty) lista.add(Tarea(nueva.text.trim()));
                Navigator.pop(ctx);
              },
              child: const Text('Listo'),
            ),
          ],
        ),
      ),
    );
    set(() {});
  }
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

  Future<void> _importarStoryboard() async {
    try {
      final r = await Plataforma.abrir();
      if (r == null) return;
      final (_, n) = aplicarStoryboard(p, r.$2);
      await _guardar();
      _avisar(n == 0
          ? 'El storyboard no cambió ninguna escena (¿coinciden con el guion?)'
          : 'Storyboard: $n escenas actualizadas');
    } catch (e) {
      _avisar('No pude leer el storyboard: $e');
    }
  }

  Future<void> _informe() async {
    try {
      final ok = await Plataforma.guardar(
          '${nombreArchivo(p.nombre)}_avance.pdf', 'application/pdf', escribirInforme(p));
      _avisar(ok ? 'Informe guardado (PDF)' : 'Exportación cancelada');
    } catch (e) {
      _avisar('No pude crear el informe: $e');
    }
  }

  /// Lee de la carpeta compartida el guion (.anms) y el storyboard (.anmb) de esta película,
  /// los aplica y deja ahí el plan (.anmp) y el informe en PDF.
  Future<void> _sincronizarCarpeta() async {
    final a = widget.almacen;
    try {
      if (a.carpetaUri.isEmpty) {
        final r = await Plataforma.elegirCarpeta();
        if (r == null) return;
        a.carpetaUri = r.$1;
        a.carpetaNombre = r.$2;
        await a.guardarAjustes();
      }
      _avisar('Revisando ${a.carpetaNombre}…');
      final archivos = await Plataforma.listarCarpeta(a.carpetaUri);
      archivos.sort((x, y) => y.$2.compareTo(x.$2)); // los más nuevos primero
      var guion = false, story = 0;
      for (final (nombre, _) in archivos) {
        final n = nombre.toLowerCase();
        if (!guion && n.endsWith('.anms')) {
          final b = await Plataforma.leerDeCarpeta(a.carpetaUri, nombre);
          if (b == null) continue;
          final id = idDeGuion(b);
          if (p.guionId.isNotEmpty && id != p.guionId) continue;
          sincronizarConGuion(p, b);
          guion = true;
        }
      }
      for (final (nombre, _) in archivos) {
        if (!nombre.toLowerCase().endsWith('.anmb')) continue;
        final b = await Plataforma.leerDeCarpeta(a.carpetaUri, nombre);
        if (b == null) continue;
        final id = idDeStoryboard(b);
        if (p.guionId.isNotEmpty && id.isNotEmpty && id != p.guionId) continue;
        story += aplicarStoryboard(p, b).$2;
        break;
      }
      await _guardar();
      await Plataforma.escribirEnCarpeta(a.carpetaUri, '${nombreArchivo(p.nombre)}.anmp', escribirAnmp(p));
      await Plataforma.escribirEnCarpeta(
          a.carpetaUri, '${nombreArchivo(p.nombre)}_avance.pdf', escribirInforme(p));
      _avisar([
        guion ? 'Guion actualizado' : 'No encontré el guion de esta película',
        if (story > 0) 'storyboard: $story escenas',
        'plan e informe copiados en ${a.carpetaNombre}',
      ].join(' · '));
    } catch (e) {
      _avisar('No pude usar la carpeta: $e');
    }
  }

  Future<void> _cambiarCarpeta() async {
    final r = await Plataforma.elegirCarpeta();
    if (r == null) return;
    widget.almacen
      ..carpetaUri = r.$1
      ..carpetaNombre = r.$2;
    await widget.almacen.guardarAjustes();
    _avisar('Carpeta: ${r.$2}');
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
    final tareasTemp = {
      for (final x in e.tareas.entries) x.key: x.value.map((t) => Tarea(t.texto, hecha: t.hecha)).toList()
    };
    final dur = TextEditingController(text: e.segundos >= 0 ? '${e.segundos}' : '');
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
              const SizedBox(height: 12),
              TextField(
                controller: dur,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Duración en segundos (se calcula del guion)',
                    border: OutlineInputBorder()),
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
                        InkWell(
                          onTap: () => _editarTareas(et, tareasTemp.putIfAbsent(et, () => []), set),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              (tareasTemp[et] ?? []).isEmpty
                                  ? '+ checklist'
                                  : '☑ ${(tareasTemp[et] ?? []).where((t) => t.hecha).length}/${(tareasTemp[et] ?? []).length}',
                              style: const TextStyle(fontSize: 11, color: Tema.textoSuave),
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
        ..fechas = fechasTemp
        ..tareas = {
          for (final x in tareasTemp.entries)
            if (x.value.isNotEmpty) x.key: x.value
        }
        ..segundos = int.tryParse(dur.text.trim()) ?? e.segundos;
      for (final et in etapas) {
        if ((etapasTemp[et] ?? 'pendiente') != e.estadoDe(et)) {
          e.ponerEstado(et, etapasTemp[et] ?? 'pendiente');
        }
      }
      if (nueva) p.escenas.add(e);
    } else {
      return;
    }
    await _guardar();
  }

  void _cambiarEstado(Escena e, String etapa) {
    e.ponerEstado(etapa, siguienteEstado(e.estadoDe(etapa)));
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
    final visibles = _visibles();
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
          _selectorFiltro(),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Toca una casilla para avanzar su estado, o el nombre de una etapa para marcarla en todas.',
                style: TextStyle(color: Tema.textoSuave, fontSize: 12)),
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
                  InkWell(
                    onTap: () => _marcarTodas(et),
                    child: SizedBox(
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
                  ),
              ]),
              const Divider(color: Tema.borde),
              Expanded(
                child: ListView.builder(
                  itemCount: visibles.length,
                  itemBuilder: (_, k) {
                    final (numero, e) = visibles[k];
                    final i = numero - 1;
                    final nuevoActo = e.acto.isNotEmpty && (k == 0 || visibles[k - 1].$2.acto != e.acto);
                    final fila = Row(children: [
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
                    if (!nuevoActo) return fila;
                    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 0, 4),
                        child: Text(e.acto.toUpperCase(),
                            style: const TextStyle(
                                color: Tema.coral, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                      ),
                      fila,
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
    if (_filtro != 'todas') {
      final v = _visibles();
      return Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: Row(children: [_selectorFiltro()])),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 96), children: [
            for (final (n, e) in v) _tarjetaEscena(n, e, key: ValueKey(e.id)),
            if (v.isEmpty)
              const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('Ninguna escena cumple el filtro.'))),
          ]),
        ),
      ]);
    }
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: Row(children: [
        _selectorFiltro(),
        const SizedBox(width: 12),
        const Expanded(child: Text('Mantén presionada una escena para cambiar el orden.',
            style: TextStyle(color: Tema.textoSuave, fontSize: 12))),
      ])),
      Expanded(child: ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      itemCount: p.escenas.length,
      onReorder: (a, b) {
        if (b > a) b--;
        final e = p.escenas.removeAt(a);
        p.escenas.insert(b, e);
        _guardar();
      },
      itemBuilder: (_, i) => _tarjetaEscena(i + 1, p.escenas[i], key: ValueKey(p.escenas[i].id)),
    )),
    ]);
  }

  Widget _tarjetaEscena(int numero, Escena e, {Key? key}) {
        final i = numero - 1;
        final enCurso = etapas.where((et) => e.estadoDe(et) != 'pendiente' && e.estadoDe(et) != 'hecho');
        return Card(
          key: key,
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
                e.resumenEtapas,
                if (e.segundos > 0) duracionTexto(e.segundos),
                if (e.acto.isNotEmpty) e.acto,
                if (enCurso.isNotEmpty) 'En curso: ${enCurso.join(', ')}',
                if (e.fueraDelGuion) '⚠ Ya no está en el guion',
              ].join(' · ')),
            ]),
          ),
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
      const SizedBox(height: 24),
      _tiempoYRitmo(),
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

  Widget _dato(String valor, String etiqueta) => Container(
        width: 170,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Tema.superficie,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Tema.borde)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(valor, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(etiqueta, style: const TextStyle(color: Tema.textoSuave, fontSize: 12)),
        ]),
      );

  Future<void> _elegirMeta() async {
    final actual = DateTime.tryParse(p.fechaMeta);
    final f = await showDatePicker(
        context: context,
        helpText: 'Fecha meta (estreno o entrega final)',
        initialDate: actual ?? DateTime.now().add(const Duration(days: 180)),
        firstDate: DateTime(2020),
        lastDate: DateTime(2040));
    if (f == null) return;
    p.fechaMeta = fechaTexto(f);
    await _guardar();
  }

  Widget _tiempoYRitmo() {
    final ritmo = p.ritmoSemanal;
    final fin = p.finEstimado;
    final meta = DateTime.tryParse(p.fechaMeta);
    final necesario = p.ritmoNecesario;
    String n(double v) => v.toStringAsFixed(v < 10 ? 1 : 0);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Tiempo y ritmo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      const SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 10, children: [
        _dato(duracionTexto(p.segundosTotales), 'duración total del guion'),
        _dato(duracionTexto(p.segundosTerminados), 'de película terminada'),
        _dato(duracionTexto(p.segundosAvanzados.round()), 'equivalente avanzado'),
        _dato('${n(ritmo)} / semana', 'etapas terminadas (últimas 4 semanas)'),
        _dato(n(p.etapasFaltantes), 'etapas que faltan'),
        _dato(fin == null ? '—' : '${fechaBonita(fin)} ${fin.year}', 'fin estimado a tu ritmo'),
      ]),
      const SizedBox(height: 14),
      Card(
        child: ListTile(
          leading: const Icon(Icons.flag, color: Tema.dorado),
          title: Text(meta == null
              ? 'Pon una fecha meta (estreno o entrega final)'
              : 'Meta: ${fechaBonita(meta)} de ${meta.year}'),
          subtitle: Text(meta == null
              ? 'Plan te dirá cuánto tienes que avanzar cada semana.'
              : necesario == null
                  ? 'La fecha meta ya pasó.'
                  : 'Necesitas ${n(necesario)} etapas por semana. '
                      '${ritmo >= necesario ? 'Vas bien ✓' : 'Vas a ${n(ritmo)}: hay que acelerar.'}'),
          trailing: const Icon(Icons.edit_calendar),
          onTap: _elegirMeta,
        ),
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
                case 'board':
                  _importarStoryboard();
                  break;
                case 'informe':
                  _informe();
                  break;
                case 'carpeta':
                  _sincronizarCarpeta();
                  break;
                case 'cambiarCarpeta':
                  _cambiarCarpeta();
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
                  value: 'board',
                  child: ListTile(
                      leading: Icon(Icons.view_carousel),
                      title: Text('Actualizar storyboard desde Board (.anmb)'))),
              PopupMenuItem(
                  value: 'carpeta',
                  child: ListTile(
                      leading: Icon(Icons.sync),
                      title: Text('Sincronizar con la carpeta del PC'),
                      subtitle: Text('Lee guion y storyboard; deja plan e informe'))),
              PopupMenuItem(
                  value: 'cambiarCarpeta',
                  child: ListTile(leading: Icon(Icons.folder_shared), title: Text('Cambiar carpeta'))),
              PopupMenuDivider(),
              PopupMenuItem(
                  value: 'informe',
                  child: ListTile(leading: Icon(Icons.picture_as_pdf), title: Text('Informe de avance (PDF)'))),
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
