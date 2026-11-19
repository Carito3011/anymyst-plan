// Anymyst Plan — plan de producción para películas animadas. Parte de la suite Anymyst.
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'almacen.dart';
import 'archivos.dart';
import 'modelo.dart';
import 'proyecto.dart';
import 'tema.dart';

const version = '0.4.1';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Plataforma.iniciar();
  runApp(const AnymystPlan());
}

class AnymystPlan extends StatelessWidget {
  const AnymystPlan({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Anymyst Plan',
        debugShowCheckedModeBanner: false,
        theme: Tema.tema,
        home: const Inicio(),
      );
}

class Inicio extends StatefulWidget {
  const Inicio({super.key});

  @override
  State<Inicio> createState() => _InicioState();
}

class _InicioState extends State<Inicio> {
  final Almacen _almacen = Almacen();
  List<Proyecto>? _proyectos;
  bool _iniciado = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (!_iniciado) {
      await _almacen.iniciar();
      _iniciado = true;
      Plataforma.alRecibir = (n, b) => _recibirGuion(b);
      final r = await Plataforma.archivoRecibido();
      if (r != null) {
        final l = await _almacen.listar();
        if (mounted) setState(() => _proyectos = l);
        await _recibirGuion(r.$2);
        return;
      }
    }
    final l = await _almacen.listar();
    if (mounted) setState(() => _proyectos = l);
  }

  void _avisar(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Future<void> _abrir(Proyecto p) async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => PaginaProyecto(almacen: _almacen, proyecto: p)));
    _cargar();
  }

  Future<void> _nuevo() async {
    final n = TextEditingController();
    final d = TextEditingController();
    final s = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo proyecto'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: n,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nombre de la película')),
            TextField(controller: d, decoration: const InputDecoration(labelText: 'Director o directora')),
            TextField(
                controller: s,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Descripción')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Crear')),
        ],
      ),
    );
    if (ok != true) return;
    final p = Proyecto(
      nombre: n.text.trim().isEmpty ? 'Sin título' : n.text.trim(),
      director: d.text.trim(),
      descripcion: s.text.trim(),
    );
    await _almacen.guardar(p);
    _abrir(p);
  }

  /// Abre un .anms (crea o actualiza su proyecto) o un .anmp.
  Future<void> _importar() async {
    try {
      final r = await Plataforma.abrir();
      if (r == null) return;
      final (nombre, bytes) = r;
      if (nombre.toLowerCase().endsWith('.anmp')) {
        final p = leerAnmp(bytes);
        await _almacen.guardar(p);
        _avisar('Plan importado');
        _abrir(p);
        return;
      }
      await _recibirGuion(bytes);
    } catch (e) {
      _avisar('No pude importar: $e');
    }
  }

  /// Un guion (.anms) crea su proyecto o actualiza el que ya existe.
  Future<void> _recibirGuion(Uint8List bytes) async {
    try {
      final (guionId, _, _) = leerGuion(bytes);
      Proyecto? p;
      for (final x in await _almacen.listar()) {
        if (guionId.isNotEmpty && x.guionId == guionId) {
          p = x;
          break;
        }
      }
      p ??= Proyecto(nombre: 'Sin título');
      final (nuevas, cambiadas, fuera) = sincronizarConGuion(p, bytes);
      await _almacen.guardar(p);
      _avisar('Guion leído: $nuevas escenas nuevas, $cambiadas cambiadas'
          '${fuera > 0 ? ', $fuera ya no están en el guion' : ''}');
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
      await _abrir(p);
    } catch (e) {
      _avisar('No pude leer el guion: $e');
    }
  }

  Future<void> _borrar(Proyecto p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Borrar proyecto'),
        content: Text('¿Borrar "${p.nombre}"? Exporta un .anmp antes si quieres conservarlo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true) return;
    await _almacen.borrar(p);
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final l = _proyectos;
    return Scaffold(
      appBar: AppBar(
        title: const Text('ANYMYST PLAN'),
        actions: [
          IconButton(
            tooltip: 'Importar guion (.anms) o plan (.anmp)',
            onPressed: _importar,
            icon: const Icon(Icons.file_open),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nuevo,
        icon: const Icon(Icons.add),
        label: const Text('Proyecto'),
      ),
      body: l == null
          ? const Center(child: CircularProgressIndicator())
          : l.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.event_note, size: 64, color: Tema.coral),
                      const SizedBox(height: 12),
                      const Text('Organiza la producción de tu película',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text(
                          'Crea un proyecto o importa el guion de Anymyst Script para traer sus escenas.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Tema.textoSuave)),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                          onPressed: _importar,
                          icon: const Icon(Icons.description),
                          label: const Text('Importar guion (.anms)')),
                      TextButton.icon(
                          onPressed: _nuevo, icon: const Icon(Icons.add), label: const Text('Proyecto vacío')),
                      const SizedBox(height: 24),
                      const Text('Anymyst Plan v$version',
                          style: TextStyle(color: Tema.textoSuave, fontSize: 12)),
                    ]),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                  children: [
                    for (final p in l)
                      Card(
                        child: ListTile(
                          onTap: () => _abrir(p),
                          leading: SizedBox(
                            width: 48,
                            height: 48,
                            child: Stack(alignment: Alignment.center, children: [
                              CircularProgressIndicator(
                                value: p.avance,
                                strokeWidth: 5,
                                backgroundColor: Tema.superficieAlta,
                                color: Tema.coral,
                              ),
                              Text(porcentaje(p.avance), style: const TextStyle(fontSize: 11)),
                            ]),
                          ),
                          title: Text(p.nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text([
                            if (p.director.isNotEmpty) p.director,
                            '${p.escenas.length} escenas',
                          ].join(' · ')),
                          trailing: IconButton(
                            tooltip: 'Borrar',
                            onPressed: () => _borrar(p),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ),
                      ),
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                        child: Text('Anymyst Plan v$version',
                            style: TextStyle(color: Tema.textoSuave, fontSize: 12)),
                      ),
                    ),
                  ],
                ),
    );
  }
}
