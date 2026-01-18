import 'dart:math';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart'; 
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart'; // Asegúrate de agregar en pubspec.yaml: video_player: ^2.8.1
import 'main.dart'; 

// Notificador global para el tema
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);

// Colores globales
final List<Color> kEvalColors = [
  const Color(0xFF26547C), // Azul
  const Color(0xFF11D7A1), // Verde
  const Color(0xFFFFD166), // Amarillo
  const Color(0xFFEF476F), // Rosa
  const Color(0xFF9D4EDD), // Morado
];

// Estados de Evaluación
const List<String> kEvaluationStates = [
  'Pendiente', 'Terminada', 'No Terminada', 'Cancelada'
];

// --- HELPERS DE SEGURIDAD (ANTI-CRASH) ---
// Estos métodos evitan que la app se cierre si faltan datos o el formato es incorrecto
DateTime safeParseDate(dynamic input) {
  if (input == null) return DateTime.now();
  if (input is Timestamp) return input.toDate(); // Soporte nativo Firebase
  if (input is String) {
    try { return DateTime.parse(input); } catch (e) { return DateTime.now(); }
  }
  return DateTime.now();
}

String safeString(dynamic input, String def) {
  if (input == null) return def;
  return input.toString();
}

int safeInt(dynamic input, int def) {
  if (input == null) return def;
  if (input is int) return input;
  if (input is double) return input.toInt();
  if (input is String) return int.tryParse(input) ?? def;
  return def;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 2;
  late PageController _pageController;
  
  String? _currentProgramId;
  String _currentProgramName = "Cargando...";
  List<Map<String, dynamic>> _userPrograms = [];
  bool _isLoadingPrograms = true;

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('es');
    _pageController = PageController(initialPage: 2);
    _fetchPrograms();
    _updateStreakOnLoad();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  DocumentReference get _userDocRef {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception("Usuario no autenticado");
    return FirebaseFirestore.instance.collection('usuarios').doc(user.uid);
  }

  Future<void> _updateStreakOnLoad() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final userDoc = await _userDocRef.get();
      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>?;
        final lastLogin = data?['ultimoAcceso'] as Timestamp?;
        if (lastLogin != null) {
          final diff = DateTime.now().difference(lastLogin.toDate()).inHours;
          if (diff > 48) {
            await _userDocRef.update({'rachaActual': 0, 'ultimoAcceso': FieldValue.serverTimestamp()});
          }
        }
      }
    } catch (e) { debugPrint("Error check streak: $e"); }
  }

  Future<void> _fetchPrograms() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final snapshot = await _userDocRef.collection('programas').orderBy('createdAt').get();
      if (mounted) {
        setState(() {
          _userPrograms = snapshot.docs.map((d) => {
            'id': d.id, 
            'nombre': safeString(d.data()['nombre'], 'Sin nombre')
          }).toList();
          _isLoadingPrograms = false;
        });

        if (_userPrograms.isEmpty) {
          Future.microtask(() => _showForceCreateProgramDialog());
        } else {
          final userDoc = await _userDocRef.get();
          final selectedId = (userDoc.data() as Map<String, dynamic>?)?['programaActual'];
          
          if (selectedId != null && _userPrograms.any((p) => p['id'] == selectedId)) {
             _currentProgramId = selectedId;
             _currentProgramName = _userPrograms.firstWhere((p) => p['id'] == selectedId)['nombre'];
          } else {
             _currentProgramId = 'all_programs';
             _currentProgramName = 'Todos los programas';
          }
          setState(() {});
        }
      }
    } catch (e) { debugPrint("Error fetching: $e"); }
  }

  void _showForceCreateProgramDialog() {
    final c = TextEditingController();
    showDialog(
      context: context, barrierDismissible: false,
      builder: (ctx) => WillPopScope(onWillPop: () async => false, child: AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("Bienvenido", style: TextStyle(color: Colors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text("Ingresa el nombre de tu carrera o curso.", style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 20),
          TextField(controller: c, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: "Ej: Ingeniería", filled: true, fillColor: Color(0xFF2C2C2C)))
        ]),
        actions: [ElevatedButton(onPressed: () async {
          if (c.text.isNotEmpty) { await _createNewProgram(c.text); Navigator.pop(ctx); }
        }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF11D7A1)), child: const Text("Comenzar", style: TextStyle(color: Colors.black)))]
      ))
    );
  }

  Future<void> _createNewProgram(String name) async {
    final ref = await _userDocRef.collection('programas').add({
      'nombre': name, 'createdAt': FieldValue.serverTimestamp(), 'tipo': 'Universitario'
    });
    if (_userPrograms.isEmpty) await _userDocRef.update({'programaActual': ref.id});
    await _fetchPrograms();
  }

  void _showEditProgramDialog(Map<String, dynamic> p) {
    final c = TextEditingController(text: p['nombre']);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("Editar Programa", style: TextStyle(color: Colors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: c, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: "Nombre", labelStyle: TextStyle(color: Colors.white54), enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24))))
        ]),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () { Navigator.pop(ctx); _deleteProgram(p['id'], p['nombre']); }),
          Row(mainAxisSize: MainAxisSize.min, children: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar", style: TextStyle(color: Colors.grey))),
            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF11D7A1)), onPressed: () async {
              if (c.text.trim().isNotEmpty) {
                await _userDocRef.collection('programas').doc(p['id']).update({'nombre': c.text.trim()});
                if (_currentProgramId == p['id']) setState(() => _currentProgramName = c.text.trim());
                await _fetchPrograms();
                if(mounted) Navigator.pop(ctx);
              }
            }, child: const Text("Guardar", style: TextStyle(color: Colors.black))),
          ])
        ],
      ),
    );
  }

  Future<void> _deleteProgram(String progId, String progName) async {
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(backgroundColor: const Color(0xFF1E1E1E), title: const Text("Eliminar Programa", style: TextStyle(color: Colors.white)), content: Text("¿Eliminar '$progName'? Se borrará todo su contenido.", style: const TextStyle(color: Colors.white70)), actions: [TextButton(onPressed: ()=>Navigator.pop(ctx, false), child: const Text("Cancelar", style: TextStyle(color: Colors.grey))), TextButton(onPressed: ()=>Navigator.pop(ctx, true), child: const Text("Eliminar", style: TextStyle(color: Colors.red)))]));
    if (confirm == true) {
      await _userDocRef.collection('programas').doc(progId).delete();
      if (_currentProgramId == progId) { await _userDocRef.update({'programaActual': FieldValue.delete()}); _currentProgramId = 'all_programs'; _currentProgramName = 'Todos los programas'; }
      await _fetchPrograms();
    }
  }

  void _changeProgram(String id, String name) {
    setState(() { _currentProgramId = id; _currentProgramName = name; });
    if (id != 'all_programs') _userDocRef.update({'programaActual': id});
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, child) {
        final Color bgColor = currentMode == ThemeMode.light ? const Color(0xFFE0E0E0) : Theme.of(context).colorScheme.background;
        
        if (_isLoadingPrograms) return const Scaffold(backgroundColor: Color(0xFF121212), body: Center(child: CircularProgressIndicator()));

        // Aquí se definen las pantallas. Si SubjectsScreen da error es porque falta pegar la Parte 2 abajo.
        final screens = [
          SubjectsScreen(programId: _currentProgramId, onProgramsChanged: _fetchPrograms),
          ScheduleScreen(programId: _currentProgramId),
          HomeMainScreen(programId: _currentProgramId, programName: _currentProgramName),
          const PlansScreen(),
          ProfileScreen(onProgramChange: _fetchPrograms),
        ];

        return Scaffold(
          backgroundColor: bgColor,
          appBar: _currentIndex == 4 ? null : AppBar(
            backgroundColor: const Color(0xFF26547C), automaticallyImplyLeading: false, elevation: 0, centerTitle: true,
            title: GestureDetector(onTap: () => _showProgramSelector(), child: Row(mainAxisSize: MainAxisSize.min, children: [Flexible(child: Text(_currentProgramName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20))), const SizedBox(width: 8), const Icon(Icons.keyboard_arrow_down, color: Colors.white70)])),
          ),
          body: PageView(controller: _pageController, physics: const BouncingScrollPhysics(), onPageChanged: (i) => setState(() => _currentIndex = i), children: screens),
          bottomNavigationBar: _buildNavBar(),
        );
      }
    );
  }

  void _showProgramSelector() {
    showModalBottomSheet(context: context, backgroundColor: const Color(0xFF1E1E1E), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), builder: (ctx) => Container(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text("Mis Programas", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        ListTile(title: const Text("Todos los programas", style: TextStyle(color: Colors.white)), trailing: _currentProgramId == 'all_programs' ? const Icon(Icons.check, color: Color(0xFF11D7A1)) : null, onTap: () { _changeProgram('all_programs', 'Todos los programas'); Navigator.pop(ctx); }),
        const Divider(color: Colors.white24),
        ..._userPrograms.map((p) => ListTile(
          leading: IconButton(icon: const Icon(Icons.edit, color: Colors.white), onPressed: () { Navigator.pop(ctx); _showEditProgramDialog(p); }),
          title: Text(p['nombre'], style: const TextStyle(color: Colors.white)),
          trailing: _currentProgramId == p['id'] ? const Icon(Icons.check, color: Color(0xFF11D7A1)) : null,
          onTap: () { _changeProgram(p['id'], p['nombre']); Navigator.pop(ctx); }
        )).toList(),
        ListTile(leading: const Icon(Icons.add, color: Colors.white70), title: const Text("Nuevo programa", style: TextStyle(color: Colors.white70)), onTap: () { Navigator.pop(ctx); _showForceCreateProgramDialog(); })
      ])
    ));
  }

  Widget _buildNavBar() {
    return BottomNavigationBar(
      currentIndex: _currentIndex, onTap: (i) { setState(() => _currentIndex = i); _pageController.animateToPage(i, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut); },
      type: BottomNavigationBarType.fixed, backgroundColor: Theme.of(context).colorScheme.surface, selectedItemColor: const Color(0xFF26547C), unselectedItemColor: Colors.grey, showUnselectedLabels: true, selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.book_outlined), activeIcon: Icon(Icons.book), label: 'Materias'),
        BottomNavigationBarItem(icon: Icon(Icons.calendar_month), activeIcon: Icon(Icons.calendar_month_rounded), label: 'Agenda'),
        BottomNavigationBarItem(icon: Icon(Icons.grid_view), activeIcon: Icon(Icons.grid_view_rounded), label: 'Inicio'),
        BottomNavigationBarItem(icon: Icon(Icons.assignment_outlined), activeIcon: Icon(Icons.assignment), label: 'Planes'),
        BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Perfil'),
      ],
    );
  }
}

// --- PANTALLA DE MATERIAS ---
class SubjectsScreen extends StatefulWidget {
  final String? programId;
  final VoidCallback onProgramsChanged;
  const SubjectsScreen({super.key, required this.programId, required this.onProgramsChanged});
  @override State<SubjectsScreen> createState() => _SubjectsScreenState();
}

class _SubjectsScreenState extends State<SubjectsScreen> {
  final User? user = FirebaseAuth.instance.currentUser;
  DocumentReference get _userDocRef => FirebaseFirestore.instance.collection('usuarios').doc(user!.uid);

  @override
  Widget build(BuildContext context) {
    if (user == null) return const Center(child: Text("No autenticado"));
    Stream<List<Map<String, dynamic>>> stream;
    if (widget.programId == null || widget.programId == 'all_programs') {
      return FutureBuilder<List<Map<String, dynamic>>>(future: _fetchAllSubjects(), builder: (context, snapshot) { if (!snapshot.hasData) return const Center(child: CircularProgressIndicator()); return _buildContent(snapshot.data!, false); });
    } else {
      stream = _userDocRef.collection('programas').doc(widget.programId).collection('materias').snapshots().map((s) => s.docs.map((d) => {...d.data(), 'id': d.id, 'ref': d.reference}).toList());
      return StreamBuilder<List<Map<String, dynamic>>>(stream: stream, builder: (context, snapshot) { if (!snapshot.hasData) return const Center(child: CircularProgressIndicator()); return _buildContent(snapshot.data!, true); });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchAllSubjects() async {
    final progs = await _userDocRef.collection('programas').get();
    List<Map<String, dynamic>> all = [];
    for(var p in progs.docs) {
      final ms = await p.reference.collection('materias').get();
      for(var m in ms.docs) all.add({...m.data(), 'id': m.id, 'ref': m.reference});
    }
    return all;
  }

  Widget _buildContent(List<Map<String, dynamic>> materias, bool canEdit) {
    return Column(children: [
      if (canEdit) Padding(padding: const EdgeInsets.all(16.0), child: SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: () => _showAddSubjectDialog(), icon: const Icon(Icons.add, color: Colors.white), label: const Text("Nueva Materia", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF11D7A1), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))))),
      Expanded(child: materias.isEmpty ? const Center(child: Text("No hay materias", style: TextStyle(color: Colors.white54))) : GridView.builder(padding: const EdgeInsets.all(16), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 1.1), itemCount: materias.length, itemBuilder: (ctx, i) => _buildSubjectCard(materias[i], canEdit))),
    ]);
  }

  Widget _buildSubjectCard(Map<String, dynamic> m, bool canEdit) {
    return FutureBuilder<double>(future: _calculateAverage(m['ref']), builder: (context, snap) {
      double avg = snap.data ?? 0.0;
      return GestureDetector(onTap: canEdit ? () => _showSubjectDialog(subjectId: m['id'], initialName: safeString(m['nombre'], 'Sin nombre'), initialProf: safeString(m['profesor'], ''), initialRoom: safeString(m['aula'], ''), docRef: m['ref']) : null, child: Container(decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(20), border: Border.all(color: _getAvgColor(avg).withOpacity(0.5), width: 1.5), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 5, offset: const Offset(0, 3))]), padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text(safeString(m['nombre'], 'Materia'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))), if (canEdit) const Icon(Icons.edit, size: 16, color: Colors.white24)]),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [if(m['profesor']!=null && m['profesor']!.isNotEmpty) Text("Prof: ${m['profesor']}", maxLines: 1, style: const TextStyle(color: Colors.white54, fontSize: 12)), if(m['aula']!=null && m['aula']!.isNotEmpty) Text("Aula: ${m['aula']}", style: const TextStyle(color: Colors.white54, fontSize: 12))]),
        Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 6), decoration: BoxDecoration(color: _getAvgColor(avg).withOpacity(0.15), borderRadius: BorderRadius.circular(8)), child: Center(child: Text("Promedio: ${avg.toStringAsFixed(1)}", style: TextStyle(color: _getAvgColor(avg), fontWeight: FontWeight.bold, fontSize: 13))))
      ])));
    });
  }

  Color _getAvgColor(double avg) { if (avg >= 18) return const Color(0xFF11D7A1); if (avg >= 14) return const Color(0xFFFFD166); if (avg > 0) return const Color(0xFFEF476F); return Colors.grey; }
  Future<double> _calculateAverage(DocumentReference ref) async { try { final evals = await ref.collection('evaluaciones').get(); if (evals.docs.isEmpty) return 0.0; double sum = 0; int count = 0; for (var e in evals.docs) { final n = double.tryParse(e.data()['nota']?.toString() ?? ''); if (n != null && n > 0) { sum += n; count++; } } return count == 0 ? 0.0 : sum / count; } catch (e) { return 0.0; } }
  void _showAddSubjectDialog() => _showSubjectDialog();
  void _showSubjectDialog({String? subjectId, String? initialName, String? initialProf, String? initialRoom, DocumentReference? docRef}) {
    final nc = TextEditingController(text: initialName); final pc = TextEditingController(text: initialProf); final rc = TextEditingController(text: initialRoom);
    showDialog(context: context, builder: (ctx) => AlertDialog(backgroundColor: const Color(0xFF1E1E1E), title: Text(subjectId == null ? "Nueva Materia" : "Editar Materia", style: const TextStyle(color: Colors.white)), content: Column(mainAxisSize: MainAxisSize.min, children: [_input(nc, "Nombre", Icons.book), const SizedBox(height: 10), _input(pc, "Profesor", Icons.person), const SizedBox(height: 10), _input(rc, "Aula", Icons.meeting_room)]), actions: [if (subjectId != null) TextButton(onPressed: () async { await docRef!.delete(); Navigator.pop(ctx); }, child: const Text("Eliminar", style: TextStyle(color: Colors.red))), TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text("Cancelar", style: TextStyle(color: Colors.grey))), ElevatedButton(onPressed: () async { if(nc.text.isEmpty) return; final data = {'nombre': nc.text, 'profesor': pc.text, 'aula': rc.text}; if(subjectId != null) { await docRef!.update(data); } else { await _userDocRef.collection('programas').doc(widget.programId).collection('materias').add({...data, 'createdAt': FieldValue.serverTimestamp()}); } Navigator.pop(ctx); }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF11D7A1)), child: const Text("Guardar", style: TextStyle(color: Colors.black)))]));
  }
  Widget _input(TextEditingController c, String h, IconData i) => TextField(controller: c, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: h, hintStyle: const TextStyle(color: Colors.white30), prefixIcon: Icon(i, color: Colors.white70), filled: true, fillColor: const Color(0xFF2C2C2C), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))));
}

// --- PANTALLA DE AGENDA ---
class ScheduleScreen extends StatefulWidget { final String? programId; const ScheduleScreen({super.key, this.programId}); @override State<ScheduleScreen> createState() => _ScheduleScreenState(); }
class _ScheduleScreenState extends State<ScheduleScreen> {
  DateTime _focusedDay = DateTime.now(); DateTime _selectedDay = DateTime.now(); Map<DateTime, List<Map<String, dynamic>>> _events = {}; bool _isLoading = true; int _streak = 0; String _filter = 'Todo';
  @override void didUpdateWidget(ScheduleScreen old) { super.didUpdateWidget(old); if(old.programId!=widget.programId) _loadEvents(); }
  @override void initState() { super.initState(); _loadEvents(); _loadStreak(); }
  Future<void> _loadStreak() async { final u = FirebaseAuth.instance.currentUser; if(u==null)return; final d = await FirebaseFirestore.instance.collection('usuarios').doc(u.uid).get(); if(mounted) setState(() => _streak = safeInt(d.data()?['rachaActual'], 0)); }
  Future<void> _loadEvents() async {
    final u = FirebaseAuth.instance.currentUser; if(u==null)return;
    try {
      Map<DateTime, List<Map<String, dynamic>>> e = {}; List<DocumentSnapshot> progs = [];
      if(widget.programId == 'all_programs' || widget.programId == null) { final s = await FirebaseFirestore.instance.collection('usuarios').doc(u.uid).collection('programas').get(); progs = s.docs; } else { final d = await FirebaseFirestore.instance.collection('usuarios').doc(u.uid).collection('programas').doc(widget.programId).get(); if(d.exists) progs = [d]; }
      for(var p in progs) {
        final ms = await p.reference.collection('materias').get();
        for(var m in ms.docs) {
          final evs = await m.reference.collection('evaluaciones').get();
          for(var doc in evs.docs) {
            final data = doc.data();
            // AUTO-CORRECCIÓN DE FECHAS (Timestamp a String)
            if (data['fecha'] is Timestamp) {
               String iso = (data['fecha'] as Timestamp).toDate().toIso8601String();
               doc.reference.update({'fecha': iso}); 
               data['fecha'] = iso;
            }
            DateTime dt = safeParseDate(data['fecha']);
            DateTime k = DateTime(dt.year, dt.month, dt.day);
            if(e[k]==null) e[k]=[];
            e[k]!.add({
              ...data, 
              'id': doc.id, 
              'materia': safeString(m['nombre'], 'Sin Materia'), 
              'nombre': safeString(data['nombre'], 'Evaluación'), 
              'estado': safeString(data['estado'], 'Pendiente'), 
              'color': safeInt(data['color'], 0xFF26547C)
            });
          }
        }
      }
      if(mounted) setState(() { _events = e; _isLoading=false; });
    } catch(e){ debugPrint("$e"); }
  }
  bool _shouldInclude(DateTime dt) { if (_filter == 'Todo') return true; final now = DateTime.now(); final diff = now.difference(dt).inDays; if (_filter == 'Último Año') return diff <= 365; if (_filter == 'Últimos 30 dias') return diff <= 30; if (_filter == 'Últimos 15 días') return diff <= 15; if (_filter == 'Última semana') return diff <= 7; return true; }
  @override Widget build(BuildContext context) {
    int terminadas=0, pendientes=0, calificadas=0, noTerminadas=0, canceladas=0;
    _events.forEach((dt, list) { if(_shouldInclude(dt)) { for(var ev in list) { switch(ev['estado']) { case 'Terminada': terminadas++; break; case 'Pendiente': pendientes++; break; case 'Calificada': calificadas++; break; case 'No Terminada': noTerminadas++; break; case 'Cancelada': canceladas++; break; default: pendientes++; } } } });
    return Scaffold(backgroundColor: const Color(0xFF121212), body: _isLoading ? const Center(child: CircularProgressIndicator()) : SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [IconButton(icon: const Icon(Icons.chevron_left, color: Colors.white), onPressed: () => setState(() => _focusedDay = DateTime(_focusedDay.year, _focusedDay.month - 1))), Text(DateFormat('MMMM yyyy', 'es').format(_focusedDay).toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)), IconButton(icon: const Icon(Icons.chevron_right, color: Colors.white), onPressed: () => setState(() => _focusedDay = DateTime(_focusedDay.year, _focusedDay.month + 1)))]),
      const SizedBox(height: 10), AnimatedSwitcher(duration: const Duration(milliseconds: 400), child: _buildMonthGrid(key: ValueKey(_focusedDay.month))),
      const SizedBox(height: 20), const Divider(color: Colors.white24, thickness: 1), const SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Estadísticas", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)), DropdownButton<String>(value: _filter, dropdownColor: const Color(0xFF1E1E1E), underline: Container(), icon: const Icon(Icons.filter_list, color: Color(0xFF11D7A1)), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), items: ['Todo', 'Último Año', 'Últimos 30 dias', 'Últimos 15 días', 'Última semana'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setState(() => _filter = v!))]),
      const SizedBox(height: 16), Container(width: double.infinity, padding: const EdgeInsets.all(15), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFEF476F), Color(0xFF9D4EDD)]), borderRadius: BorderRadius.circular(15)), child: Column(children: [Text("$_streak", style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)), const Text("Días en Racha 🔥", style: TextStyle(color: Colors.white70, fontSize: 14))])),
      const SizedBox(height: 10), Row(children: [Expanded(child: _statBox("Terminadas", terminadas, const Color(0xFF11D7A1))), const SizedBox(width: 10), Expanded(child: _statBox("Pendientes", pendientes, const Color(0xFF26547C)))]),
      const SizedBox(height: 10), Row(children: [Expanded(child: _statBox("Calificadas", calificadas, const Color(0xFFFFD166))), const SizedBox(width: 10), Expanded(child: _statBox("No Terminadas", noTerminadas, Colors.orange))]),
      const SizedBox(height: 10), SizedBox(width: double.infinity, child: _statBox("Canceladas", canceladas, Colors.red)),
    ])));
  }
  Widget _statBox(String label, int count, Color color) => Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(15), border: Border.all(color: color.withOpacity(0.5))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(count.toString(), style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)), Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12))]));
  Widget _buildMonthGrid({Key? key}) { final daysInMonth = DateUtils.getDaysInMonth(_focusedDay.year, _focusedDay.month); final firstWeekday = DateTime(_focusedDay.year, _focusedDay.month, 1).weekday; return GridView.builder(key: key, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: 0.8), itemCount: daysInMonth + (firstWeekday - 1), itemBuilder: (ctx, i) { if (i < firstWeekday - 1) return const SizedBox(); final day = i - (firstWeekday - 1) + 1; final date = DateTime(_focusedDay.year, _focusedDay.month, day); final dayEvents = _events[DateTime(date.year, date.month, date.day)] ?? []; final isSelected = date.day == _selectedDay.day && date.month == _selectedDay.month; return GestureDetector(onTap: () { setState(() => _selectedDay = date); if(dayEvents.isNotEmpty) _showDayEvents(date); }, child: Container(margin: const EdgeInsets.all(2), decoration: BoxDecoration(color: isSelected ? const Color(0xFF26547C) : (dayEvents.isNotEmpty ? const Color(0xFF1E1E1E) : Colors.transparent), borderRadius: BorderRadius.circular(8), border: dayEvents.isNotEmpty ? Border.all(color: const Color(0xFF11D7A1), width: 1) : null), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text("$day", style: TextStyle(color: isSelected ? Colors.white : Colors.white70)), if(dayEvents.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: dayEvents.take(3).map((e) => Container(width: 6, height: 6, margin: const EdgeInsets.symmetric(horizontal: 1), decoration: BoxDecoration(color: Color(e['color']), shape: BoxShape.circle))).toList()))]))); }); }
  void _showDayEvents(DateTime date) { final events = _events[DateTime(date.year, date.month, date.day)] ?? []; String mesNombre = DateFormat('MMMM', 'es').format(date); String titulo = "Evaluaciones del día ${date.day} de ${mesNombre[0].toUpperCase()}${mesNombre.substring(1)}"; showModalBottomSheet(context: context, backgroundColor: const Color(0xFF1E1E1E), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), builder: (ctx) => Container(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(titulo, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 15), ...events.map((e) => ListTile(contentPadding: EdgeInsets.zero, leading: CircleAvatar(backgroundColor: Color(e['color']), radius: 6), title: Text(e['nombre'], style: const TextStyle(color: Colors.white)), subtitle: Text(e['materia'], style: const TextStyle(color: Colors.white70)), trailing: Text(e['estado'], style: TextStyle(color: e['estado']=='Terminada'?const Color(0xFF11D7A1):Colors.grey, fontSize: 12)))).toList()]))); }
}

// --- HOME DASHBOARD (INICIO) ---
class HomeMainScreen extends StatefulWidget {
  final String? programId;
  final String programName;
  const HomeMainScreen({super.key, required this.programId, required this.programName});
  @override State<HomeMainScreen> createState() => _HomeMainScreenState();
}

class _HomeMainScreenState extends State<HomeMainScreen> with SingleTickerProviderStateMixin {
  bool _isFabExpanded = false;
  late AnimationController _fabController;
  late Animation<double> _fabScale;
  List<Map<String, dynamic>> _evaluaciones = [];
  int _index = 0;
  String _userName = "";
  final List<String> _monthsEs = ['ENE', 'FEB', 'MAR', 'ABR', 'MAY', 'JUN', 'JUL', 'AGO', 'SEP', 'OCT', 'NOV', 'DIC'];

  @override void initState() { 
    super.initState(); 
    _fabController = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
    _fabScale = CurvedAnimation(parent: _fabController, curve: Curves.easeOutBack);
    _loadData();
  }
  @override void dispose() { _fabController.dispose(); super.dispose(); }
  @override void didUpdateWidget(HomeMainScreen old) { super.didUpdateWidget(old); if(old.programId!=widget.programId) _loadData(); }

  Future<void> _loadData() async {
    final u = FirebaseAuth.instance.currentUser; if(u==null)return;
    try {
      final userDoc = await FirebaseFirestore.instance.collection('usuarios').doc(u.uid).get();
      if(mounted) setState(() => _userName = (safeString(userDoc.data()?['nombre'], "Usuario")).split(' ')[0]);
      _loadEvaluaciones();
    } catch(e) { debugPrint("Error loading user: $e"); }
  }

  Future<void> _loadEvaluaciones() async {
    final user = FirebaseAuth.instance.currentUser; if(user==null)return;
    List<Map<String, dynamic>> all = [];
    try {
      List<DocumentSnapshot> progs = [];
      final pRef = FirebaseFirestore.instance.collection('usuarios').doc(user.uid).collection('programas');
      if(widget.programId == 'all_programs' || widget.programId == null) {
        final s = await pRef.get(); progs = s.docs;
      } else {
        final d = await pRef.doc(widget.programId).get(); if(d.exists) progs=[d];
      }
      for(var p in progs) {
        final ms = await p.reference.collection('materias').get();
        for(var m in ms.docs) {
          final es = await m.reference.collection('evaluaciones').get();
          for(var e in es.docs) {
            var d = e.data();
            
            // --- AUTO-CORRECCIÓN ---
            if (d['fecha'] is Timestamp) {
               String iso = (d['fecha'] as Timestamp).toDate().toIso8601String();
               e.reference.update({'fecha': iso});
               d['fecha'] = iso;
            }
            DateTime dt = safeParseDate(d['fecha']);
            
            all.add({
              ...d, 
              'id': e.id, 
              'ref': e.reference, 
              'materia': safeString(m['nombre'], 'Sin Materia'), 
              'aula': safeString(m['aula'], ''), 
              'fecha': dt, 
              'materiaId': m.id,
              'colorInt': safeInt(d['color'], 0xFF26547C), 
              'nombre': safeString(d['nombre'], 'Sin Título'),
              'estado': safeString(d['estado'], 'Pendiente'),
              'tipo': safeString(d['tipo'], 'General'),
              'nota': safeString(d['nota'], '0')
            });
          }
        }
      }
      all.sort((a,b) {
        bool aDone = a['estado'] == 'Terminada' || a['estado'] == 'Calificada';
        bool bDone = b['estado'] == 'Terminada' || b['estado'] == 'Calificada';
        if (aDone && !bDone) return 1;
        if (!aDone && bDone) return -1;
        return a['fecha'].compareTo(b['fecha']);
      });
      if(mounted) setState(() { _evaluaciones = all; if(_index >= all.length) _index=0; });
    } catch(e) { debugPrint("Error loading: $e"); }
  }

  void _updateStreak() async {
    final u = FirebaseAuth.instance.currentUser; if(u==null)return;
    await FirebaseFirestore.instance.collection('usuarios').doc(u.uid).update({'rachaActual': FieldValue.increment(1)});
  }

  @override
  Widget build(BuildContext context) {
    int firstCompletedIdx = -1;
    for(int i=0; i<_evaluaciones.length; i++) {
      if(_evaluaciones[i]['estado'] == 'Terminada' || _evaluaciones[i]['estado'] == 'Calificada') {
        firstCompletedIdx = i; break;
      }
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 30),
                decoration: const BoxDecoration(color: Color(0xFF26547C), borderRadius: BorderRadius.vertical(bottom: Radius.circular(30))),
                width: double.infinity,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text("¡Hola, $_userName!", style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                  const Text("Facilita tu próxima actividad", style: TextStyle(color: Colors.white70))
                ]),
              ),
              Expanded(
                child: _evaluaciones.isEmpty 
                  ? const Center(child: Text("Todo al día 🎉", style: TextStyle(color: Colors.white, fontSize: 18)))
                  : Center(child: SingleChildScrollView(child: _buildMainCard(_evaluaciones.isNotEmpty ? _evaluaciones[_index] : {})))
              ),
              if(_evaluaciones.isNotEmpty) Container(
                height: 120, margin: const EdgeInsets.only(bottom: 20),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _evaluaciones.length,
                  itemBuilder: (c, i) {
                    final ev = _evaluaciones[i];
                    Color evColor = Color(ev['colorInt']);
                    bool isSel = _index==i;
                    return Row(
                      children: [
                        if (i == firstCompletedIdx && i > 0) Container(width: 2, height: 60, color: Colors.grey, margin: const EdgeInsets.symmetric(horizontal: 8)),
                        GestureDetector(
                          onTap: ()=>setState(()=>_index=i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 140, margin: const EdgeInsets.only(right: 10, top: 10, bottom: 10), padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: isSel ? evColor : const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(15), border: isSel ? null : Border.all(color: Colors.white12)),
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Text(ev['nombre']??'', maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: TextStyle(color: isSel?Colors.white:Colors.white70, fontWeight: FontWeight.bold, fontSize: 14)),
                              const SizedBox(height: 5),
                              Text(DateFormat('dd/MM').format(ev['fecha']), style: TextStyle(color: isSel?Colors.white:Colors.white30, fontSize: 12)),
                            ]),
                          ),
                        ),
                      ],
                    );
                  }
                ),
              ),
              const SizedBox(height: 70) 
            ],
          ),
          if(_isFabExpanded) Positioned.fill(child: GestureDetector(onTap: ()=>_toggleFab(), child: Container(color: Colors.black54))),
          if(_isFabExpanded) ..._buildSatellites(),
          Positioned(
            right: 20, bottom: 20,
            child: FloatingActionButton(
              onPressed: _toggleFab,
              backgroundColor: const Color(0xFF26547C),
              child: Icon(_isFabExpanded ? Icons.close : Icons.add, color: Colors.white),
            )
          )
        ],
      ),
    );
  }

  Widget _buildMainCard(Map<String, dynamic> ev) {
    if(ev.isEmpty) return const SizedBox();
    Color color = Color(ev['colorInt']??0xFF26547C);
    String displayStatus = ev['estado'];
    if(displayStatus == 'Calificada') displayStatus = 'Terminada'; 

    DateTime dt = ev['fecha'];
    String dayNum = dt.day.toString();
    String monthAbbr = _monthsEs[dt.month - 1]; 
    String time = DateFormat('hh:mm a').format(dt);

    return Container(
      width: 320, height: 420, 
      margin: const EdgeInsets.all(20), padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(30), border: Border.all(color: color, width: 2), boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 10, offset: const Offset(0,5))]),
      child: Column(
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Chip(label: Text(ev['tipo']??'General'), backgroundColor: color.withOpacity(0.2), labelStyle: TextStyle(color: color)),
            IconButton(icon: const Icon(Icons.edit, color: Colors.white54), onPressed: () => showDialog(context: context, builder: (c) => AddEvaluationDialog(currentProgramId: widget.programId!, existingEval: ev)).then((_)=>_loadData())),
          ]),
          const SizedBox(height: 10),
          Text(ev['nombre']??'', textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Column(children: [Text(dayNum, style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: color, height: 1)), Text(monthAbbr, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white))]),
              Container(width: 1, height: 60, color: Colors.white24, margin: const EdgeInsets.symmetric(horizontal: 20)),
              Text(time, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w300, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            Row(children: [Icon(Icons.book, size: 16, color: color), const SizedBox(width: 5), Text(ev['materia']??'', style: const TextStyle(color: Colors.white70))]),
            Row(children: [Icon(Icons.meeting_room, size: 16, color: color), const SizedBox(width: 5), Text(ev['aula']??'', style: const TextStyle(color: Colors.white70))]),
          ]),
          const Spacer(),
          Row(children: [
            Expanded(child: SizedBox(height: 55, child: ElevatedButton.icon(icon: const Icon(Icons.star, size: 18), onPressed: () => _showGradingDialog(ev), style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, foregroundColor: const Color(0xFFFFD166), elevation: 0, side: const BorderSide(color: Color(0xFFFFD166), width: 2), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), label: Text(ev['nota']=='0'?"Calificar":"${ev['nota']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))))),
            const SizedBox(width: 15),
            Expanded(child: Container(height: 55, padding: const EdgeInsets.symmetric(horizontal: 15), decoration: BoxDecoration(color: const Color(0xFF11D7A1), borderRadius: BorderRadius.circular(15)), child: DropdownButtonHideUnderline(child: DropdownButton<String>(value: kEvaluationStates.contains(displayStatus) ? displayStatus : 'Pendiente', dropdownColor: const Color(0xFF1E1E1E), isExpanded: true, icon: const Icon(Icons.keyboard_arrow_down, color: Colors.black), style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16), items: kEvaluationStates.map((s) => DropdownMenuItem(value: s, child: Center(child: Text(s, style: TextStyle(color: s==displayStatus?Colors.black:Colors.white))))).toList(), onChanged: (v) async { if(v!=null) { await (ev['ref'] as DocumentReference).update({'estado': v}); if(v=='Terminada') _updateStreak(); _loadData(); } })))),
          ]),
        ],
      ),
    );
  }

  void _showGradingDialog(Map<String, dynamic> ev) {
    final c = TextEditingController(text: ev['nota']=='0'?'':ev['nota']);
    showDialog(context: context, builder: (ctx) => AlertDialog(backgroundColor: const Color(0xFF1E1E1E), title: const Text("Calificar", style: TextStyle(color: Colors.white)), content: TextField(controller: c, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white, fontSize: 24), textAlign: TextAlign.center, decoration: const InputDecoration(hintText: "0-20", hintStyle: TextStyle(color: Colors.white24))), actions: [ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD166)), onPressed: () async { if(c.text.isNotEmpty) { await (ev['ref'] as DocumentReference).update({'nota': c.text, 'estado': 'Calificada'}); _updateStreak(); Navigator.pop(ctx); _loadData(); } }, child: const Text("Guardar", style: TextStyle(color: Colors.black)))]));
  }

  void _toggleFab() { setState(() => _isFabExpanded = !_isFabExpanded); if(_isFabExpanded) _fabController.forward(); else _fabController.reverse(); }
  
  List<Widget> _buildSatellites() {
    const double radius = 100; 
    const double angle1 = -pi / 2.2; 
    const double angle2 = -pi;       
    return [
      Positioned(bottom: 35 + radius * sin(angle2).abs(), right: 25 + radius * cos(angle2).abs(), child: ScaleTransition(scale: _fabScale, child: FloatingActionButton(heroTag: 'add2', backgroundColor: const Color(0xFFFFD166), onPressed: () { _toggleFab(); _showAddSubjectDialog(context); }, child: const Icon(Icons.book, color: Colors.black)))),
      Positioned(bottom: 25 + radius * sin(angle1).abs(), right: 25 + radius * cos(angle1).abs(), child: ScaleTransition(scale: _fabScale, child: FloatingActionButton(heroTag: 'add1', backgroundColor: const Color(0xFF11D7A1), onPressed: () { _toggleFab(); showDialog(context: context, builder: (c) => AddEvaluationDialog(currentProgramId: widget.programId!)).then((_)=>_loadData()); }, child: const Icon(Icons.assignment_add, color: Colors.black)))),
    ];
  }

  void _showAddSubjectDialog(BuildContext ctx) {
    if(widget.programId == null || widget.programId == 'all_programs') return;
    final n = TextEditingController(); final p = TextEditingController(); final r = TextEditingController();
    showDialog(context: ctx, builder: (c) => AlertDialog(backgroundColor: const Color(0xFF1E1E1E), title: const Text("Nueva Materia", style: TextStyle(color: Colors.white)), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: n, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: "Nombre", filled: true, fillColor: Color(0xFF2C2C2C))), const SizedBox(height: 10), TextField(controller: p, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: "Profesor", filled: true, fillColor: Color(0xFF2C2C2C))), const SizedBox(height: 10), TextField(controller: r, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: "Aula", filled: true, fillColor: Color(0xFF2C2C2C)))]), actions: [ElevatedButton(onPressed: () async { if(n.text.isNotEmpty) { await FirebaseFirestore.instance.collection('usuarios').doc(FirebaseAuth.instance.currentUser!.uid).collection('programas').doc(widget.programId).collection('materias').add({'nombre': n.text, 'profesor': p.text, 'aula': r.text, 'createdAt': FieldValue.serverTimestamp()}); Navigator.pop(c); } }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF11D7A1)), child: const Text("Guardar"))]));
  }
}

class AddEvaluationDialog extends StatefulWidget {
  final String currentProgramId;
  final Map<String, dynamic>? existingEval;
  const AddEvaluationDialog({super.key, required this.currentProgramId, this.existingEval});
  @override State<AddEvaluationDialog> createState() => _AddEvaluationDialogState();
}

class _AddEvaluationDialogState extends State<AddEvaluationDialog> {
  final _titleCtrl = TextEditingController();
  String? _selectedSubjectId;
  String _selectedType = 'Examen';
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  int _selectedColor = 0xFF26547C;
  List<Map<String, dynamic>> _subjects = [];
  List<Map<String, dynamic>> _reminders = [];
  final List<String> _evalTypes = ['Examen', 'Prueba Corta', 'Trabajo', 'Proyecto', 'Oral', 'Práctica', 'Otro', 'Sin Definir'];

  @override void initState() { super.initState(); _loadSubjects(); if(widget.existingEval != null) _loadExisting(); }

  void _loadExisting() {
    final e = widget.existingEval!;
    _titleCtrl.text = safeString(e['nombre'], '');
    _selectedSubjectId = e['materiaId'];
    _selectedType = _evalTypes.contains(e['tipo']) ? e['tipo'] : 'Otro';
    _selectedColor = safeInt(e['colorInt'], 0xFF26547C);
    DateTime dt = safeParseDate(e['fecha']);
    _selectedDate = dt;
    _selectedTime = TimeOfDay.fromDateTime(dt);
  }

  Future<void> _loadSubjects() async {
    final u = FirebaseAuth.instance.currentUser; if(u==null)return;
    final s = await FirebaseFirestore.instance.collection('usuarios').doc(u.uid).collection('programas').doc(widget.currentProgramId).collection('materias').get();
    if(mounted) setState(() {
      _subjects = s.docs.map((d) => {'id': d.id, 'nombre': d['nombre']}).toList();
      if(widget.existingEval == null && _selectedSubjectId == null && _subjects.isNotEmpty) _selectedSubjectId = _subjects.first['id'];
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      contentPadding: const EdgeInsets.all(20),
      content: SizedBox(width: double.maxFinite, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        const Text("Materia", style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 5),
        Container(padding: const EdgeInsets.symmetric(horizontal: 15), decoration: BoxDecoration(color: const Color(0xFF2C2C2C), borderRadius: BorderRadius.circular(15)), child: DropdownButtonHideUnderline(child: DropdownButton<String>(value: _selectedSubjectId, isExpanded: true, dropdownColor: const Color(0xFF2C2C2C), hint: const Text("Materia", style: TextStyle(color: Colors.white54)), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), items: _subjects.map((s) => DropdownMenuItem(value: s['id'] as String, child: Text(s['nombre']))).toList(), onChanged: (v) => setState(() => _selectedSubjectId = v)))),
        const SizedBox(height: 15),
        TextField(controller: _titleCtrl, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold), decoration: const InputDecoration(hintText: "Evaluación", hintStyle: TextStyle(color: Colors.white30), border: InputBorder.none, contentPadding: EdgeInsets.zero, labelText: "Título", labelStyle: TextStyle(color: Colors.white54, fontSize: 14))),
        const Divider(color: Colors.white24),
        const SizedBox(height: 15),
        Row(children: [
          Expanded(child: _dateBtn(Icons.calendar_today, DateFormat('dd/MM/yyyy').format(_selectedDate), () async { final d = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2020), lastDate: DateTime(2030)); if(d!=null) setState(()=>_selectedDate=d); })),
          const SizedBox(width: 15),
          Expanded(child: _dateBtn(Icons.access_time, _selectedTime.format(context), () async { final t = await showTimePicker(context: context, initialTime: _selectedTime); if(t!=null) setState(()=>_selectedTime=t); })),
        ]),
        const SizedBox(height: 15),
        DropdownButton<String>(value: _selectedType, dropdownColor: const Color(0xFF2C2C2C), isExpanded: true, style: const TextStyle(color: Colors.white), items: _evalTypes.map((t)=>DropdownMenuItem(value: t, child: Text(t))).toList(), onChanged: (v)=>setState(()=>_selectedType=v!)),
        const SizedBox(height: 15),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: kEvalColors.map((c) => GestureDetector(onTap: ()=>setState(()=>_selectedColor=c.value), child: Container(width: 35, height: 35, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: _selectedColor==c.value ? Border.all(color: Colors.white, width: 3) : null)))).toList()),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Recordatorios", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), if(_reminders.length < 5) IconButton(icon: const Icon(Icons.add_circle, color: Color(0xFF11D7A1)), onPressed: _addReminder)]),
        ..._reminders.asMap().entries.map((e) {
          return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFF2C2C2C), borderRadius: BorderRadius.circular(10)), child: Row(children: [
            const Icon(Icons.notifications, size: 16, color: Colors.white70),
            const SizedBox(width: 10),
            Expanded(child: GestureDetector(
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: e.value['fecha'].isAfter(_selectedDate) ? _selectedDate : e.value['fecha'], firstDate: DateTime(2020), lastDate: _selectedDate);
                if(d!=null) { final t = await showTimePicker(context: context, initialTime: e.value['hora']); if(t!=null) setState(() { _reminders[e.key]['fecha']=d; _reminders[e.key]['hora']=t; }); }
              },
              child: Text("${DateFormat('dd/MM').format(e.value['fecha'])} - ${e.value['hora'].format(context)}", style: const TextStyle(color: Colors.white))
            )),
            IconButton(icon: const Icon(Icons.delete, size: 18, color: Colors.red), onPressed: ()=>setState(()=>_reminders.removeAt(e.key)))
          ]));
        }).toList()
      ]))),
      actions: [
        if(widget.existingEval != null) IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () async { await (widget.existingEval!['ref'] as DocumentReference).delete(); Navigator.pop(context); }),
        TextButton(onPressed: ()=>Navigator.pop(context), child: const Text("Cancelar", style: TextStyle(color: Colors.grey))),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF11D7A1)), onPressed: _save, child: const Text("Guardar", style: TextStyle(color: Colors.black)))
      ],
    );
  }

  Widget _dateBtn(IconData i, String t, VoidCallback tap) => GestureDetector(onTap: tap, child: Container(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10), decoration: BoxDecoration(color: const Color(0xFF2C2C2C), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)), child: Row(children: [Icon(i, color: const Color(0xFF11D7A1), size: 16), const SizedBox(width: 5), Text(t, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))])));

  void _addReminder() { 
    DateTime rDate = _selectedDate.subtract(const Duration(days: 1));
    if(rDate.isBefore(DateTime.now())) rDate = DateTime.now(); 
    setState(() { _reminders.add({'fecha': rDate, 'hora': const TimeOfDay(hour: 8, minute: 0)}); }); 
  }

  Future<void> _save() async {
    if(_selectedSubjectId == null) return;
    final u = FirebaseAuth.instance.currentUser;
    final dt = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, _selectedTime.hour, _selectedTime.minute);
    final data = {
      'nombre': _titleCtrl.text.isEmpty ? "Evaluación" : _titleCtrl.text,
      'fecha': dt.toIso8601String(), 'tipo': _selectedType, 'color': _selectedColor,
      'nota': widget.existingEval?['nota'] ?? '0', 'estado': widget.existingEval?['estado'] ?? 'Pendiente',
    };
    if(widget.existingEval != null) {
      await (widget.existingEval!['ref'] as DocumentReference).update(data);
    } else {
      final ref = await FirebaseFirestore.instance.collection('usuarios').doc(u!.uid).collection('programas').doc(widget.currentProgramId).collection('materias').doc(_selectedSubjectId).collection('evaluaciones').add(data);
      for(var r in _reminders) {
        DateTime rd = r['fecha']; TimeOfDay rt = r['hora'];
        DateTime finalR = DateTime(rd.year, rd.month, rd.day, rt.hour, rt.minute);
        await FirebaseFirestore.instance.collection('usuarios').doc(u.uid).collection('recordatorios').add({
          'descripcion': "Recordatorio: ${_titleCtrl.text}", 
          'fecha': finalR.toIso8601String(), 'hora': "${rt.hour}:${rt.minute}", 'evaluacionId': ref.id
        });
      }
    }
    Navigator.pop(context);
  }
} 

// --- CLASE DE SIMULACIÓN DE ANUNCIO ---
class AdVideoDialog extends StatefulWidget {
  const AdVideoDialog({super.key});
  @override State<AdVideoDialog> createState() => _AdVideoDialogState();
}

class _AdVideoDialogState extends State<AdVideoDialog> {
  late VideoPlayerController _controller;
  int _secondsLeft = 15;
  Timer? _timer;
  bool _canClose = false;
  bool _videoError = false;

  @override
  void initState() {
    super.initState();
    // Asegúrate de que el nombre del archivo sea EXACTAMENTE el mismo que en tu carpeta
    _controller = VideoPlayerController.asset('assets/videos/anuncio1.mp4')
      ..initialize().then((_) {
        if (mounted) {
          setState(() {});
          _controller.play();
          _controller.setLooping(true);
          _controller.setVolume(1.0);
        }
      }).catchError((e) {
        debugPrint("Error cargando video: $e");
        if(mounted) setState(() => _videoError = true);
      });
    
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft > 0) {
        if (mounted) setState(() => _secondsLeft--);
      } else {
        _timer?.cancel();
        if (mounted) setState(() => _canClose = true);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    try { _controller.dispose(); } catch(e) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: EdgeInsets.zero, 
      child: Stack(
        children: [
          // Video de fondo
          Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.black,
            child: _videoError 
              ? const Center(child: Text("Video no disponible\nVerifica assets/videos/anuncio1.mp4", textAlign: TextAlign.center, style: TextStyle(color: Colors.white)))
              : (_controller.value.isInitialized
                  ? Center(
                      child: AspectRatio(
                        aspectRatio: _controller.value.aspectRatio,
                        child: VideoPlayer(_controller),
                      ),
                    )
                  : const Center(child: CircularProgressIndicator(color: Color(0xFF11D7A1)))),
          ),
          
          // TEXTO DEL ANUNCIO (Overlay)
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Clash Royale",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    shadows: [Shadow(color: Colors.black, blurRadius: 10, offset: Offset(0, 2))]
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "¡Prueba este nuevo juego ahora mismo y derrótalos a todos!",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    shadows: [Shadow(color: Colors.black, blurRadius: 8, offset: Offset(0, 1))]
                  ),
                ),
                const SizedBox(height: 20),
                if (_canClose)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF11D7A1),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12)
                      ),
                      child: const Text("Cerrar Anuncio", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  )
              ],
            ),
          ),

          // Contador (Arriba derecha)
          if (!_canClose) 
             Positioned(
               top: 40, 
               right: 20, 
               child: Container(
                 padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), 
                 decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)), 
                 child: Text("$_secondsLeft", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))
               )
             ),
             
          // Botón X de Cerrar (Solo aparece al final, arriba derecha como opción extra)
          if (_canClose)
            Positioned(
              top: 40, 
              right: 20, 
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30), 
                onPressed: () => Navigator.of(context).pop()
              )
            )
        ],
      ),
    );
  }
}

// --- PANTALLA DE PLANES ---
class PlansScreen extends StatelessWidget {
  const PlansScreen({super.key});
  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.diamond, size: 80, color: Color(0xFFFFD166)),
              const SizedBox(height: 20),
              const Text("Easier Premium", style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFFFFD166))),
              const SizedBox(height: 16),
              const Text("Desbloquea el poder de la IA.", textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey)),
              const SizedBox(height: 40),
              Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF26547C), Color(0xFF1E1E1E)]), borderRadius: BorderRadius.circular(24)), child: Column(children: [
                const Text("Solo \$1.99 / mes", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    showDialog(context: context, barrierDismissible: false, builder: (ctx) => const AdVideoDialog()).then((_) {
                      _showPaymentDialog(context);
                    });
                  }, 
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD166), foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))), 
                  child: const Text("Suscribirse Ahora", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))
                )
              ])),
            ],
          ),
        ),
      ),
    );
  }

  void _showPaymentDialog(BuildContext context) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: const Text("Métodos de Pago", style: TextStyle(color: Colors.white)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min, 
          children: [
            _paymentOption(ctx, "Opción 1: Banco Venezuela", "32.062.856", "0412-4671498", "(0102) Venezuela", "32062856\n04124671498\n0102"),
            const Divider(color: Colors.white24, height: 30),
            _paymentOption(ctx, "Opción 2: Banco Provincial", "31.363.029", "0412-4028015", "(0108) Provincial", "31363029\n04124028015\n0108"),
          ]
        ),
      ),
      actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text("Cerrar", style: TextStyle(color: Colors.grey)))]
    ));
  }

  Widget _paymentOption(BuildContext ctx, String title, String cedula, String telf, String banco, String rawData) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(color: Color(0xFF11D7A1), fontWeight: FontWeight.bold, fontSize: 16)),
      const SizedBox(height: 10),
      _row("Cédula:", cedula),
      _row("Número:", telf),
      _row("Banco:", banco),
      const SizedBox(height: 10),
      Center(child: ElevatedButton.icon(onPressed: () { Clipboard.setData(ClipboardData(text: rawData)); ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Datos copiados"), backgroundColor: Color(0xFF11D7A1))); Navigator.pop(ctx); }, icon: const Icon(Icons.copy, size: 16), label: const Text("Copiar Datos"), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF26547C), foregroundColor: Colors.white, visualDensity: VisualDensity.compact)))
    ]);
  }
  
  Widget _row(String l, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [Text(l, style: const TextStyle(color: Colors.grey)), const SizedBox(width: 10), Text(v, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))]));
}

// --- PANTALLA DE PERFIL ---
class ProfileScreen extends StatefulWidget {
  final VoidCallback onProgramChange;
  const ProfileScreen({super.key, required this.onProgramChange});
  @override State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic> _userData = {};
  
  @override void initState() { super.initState(); _load(); }
  
  Future<void> _load() async {
    final u = FirebaseAuth.instance.currentUser; if(u==null)return;
    final d = await FirebaseFirestore.instance.collection('usuarios').doc(u.uid).get();
    if(d.exists) setState(()=>_userData = d.data() as Map<String, dynamic>);
  }

  Future<void> _launchWhatsApp() async {
    final Uri url = Uri.parse('https://wa.me/message/FYG25DSY3ZE6J1');
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw 'No se pudo lanzar';
      }
    } catch (e) {
      debugPrint("Error launching WA: $e");
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No se pudo abrir WhatsApp"), backgroundColor: Colors.red));
    }
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16), 
        child: Column(
          children: [
            Container(width: double.infinity, padding: const EdgeInsets.all(24), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF26547C), Color(0xFF1E1E1E)]), borderRadius: BorderRadius.circular(20)), child: Column(children: [
              CircleAvatar(radius: 50, backgroundColor: const Color(0xFF11D7A1), child: Text(_userData['nombre']?.substring(0,1).toUpperCase()??'U', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white))),
              const SizedBox(height: 16),
              Text(_userData['nombre']??'Usuario', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
              Text(_userData['email']??'', style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 10),
              Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: const Color(0xFF11D7A1).withOpacity(0.2), borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFF11D7A1))), child: Text("Racha: ${_userData['rachaActual']??0} días 🔥", style: const TextStyle(color: Color(0xFF11D7A1), fontWeight: FontWeight.bold)))
            ])),
            
            const SizedBox(height: 30),

            GestureDetector(
              onTap: _launchWhatsApp,
              child: Container(
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.black, 
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF25D366), width: 2), 
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF25D366).withOpacity(0.6), 
                      blurRadius: 15, 
                      spreadRadius: 1,
                    )
                  ]
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.chat_bubble, color: Color(0xFF25D366), size: 32),
                    SizedBox(width: 15),
                    Text("Vincular con Whatsapp", style: TextStyle(color: Color(0xFF25D366), fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            
            _opt(Icons.person, "Editar Perfil", "Actualiza tus datos y contraseña", () => Navigator.push(context, MaterialPageRoute(builder: (c)=>const AccountEditScreen())).then((_)=>_load())),
            _opt(Icons.people, "Sobre Nosotros", "Conoce al equipo", () => Navigator.push(context, MaterialPageRoute(builder: (c)=>const AboutUsScreen()))),
            _opt(Icons.logout, "Cerrar Sesión", "", () => _confirmLogout(context), isLogout: true),
          ]
        )
      )
    );
  }
  Widget _opt(IconData i, String t, String s, VoidCallback tap, {bool isLogout=false}) => Card(color: const Color(0xFF1E1E1E), margin: const EdgeInsets.only(bottom: 12), child: ListTile(leading: Icon(i, color: isLogout?Colors.red:const Color(0xFF11D7A1)), title: Text(t, style: TextStyle(color: isLogout?Colors.red:Colors.white, fontWeight: FontWeight.bold)), subtitle: s.isNotEmpty?Text(s, style: const TextStyle(color: Colors.white70)):null, onTap: tap, trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white54)));

  void _confirmLogout(BuildContext context) {
    showDialog(context: context, builder: (ctx) => AlertDialog(backgroundColor: const Color(0xFF1E1E1E), title: const Text("Cerrar Sesión", style: TextStyle(color: Colors.white)), content: const Text("¿Estás seguro de que quieres salir?", style: TextStyle(color: Colors.white70)), actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text("Cancelar", style: TextStyle(color: Colors.grey))), ElevatedButton(onPressed: () async { Navigator.pop(ctx); await FirebaseAuth.instance.signOut(); if(mounted) Navigator.pushNamedAndRemoveUntil(context, '/start', (r) => false); }, style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text("Salir", style: TextStyle(color: Colors.white)))]));
  }
}

// --- EDITAR PERFIL COMPLETO ---
class AccountEditScreen extends StatefulWidget {
  const AccountEditScreen({super.key});
  @override State<AccountEditScreen> createState() => _AccountEditScreenState();
}

class _AccountEditScreenState extends State<AccountEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _birthCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController(); 
  final _oldPass = TextEditingController();
  final _newPass = TextEditingController();
  final _repPass = TextEditingController();
  
  List<Map<String, dynamic>> _countries = [];
  List<String> _states = [];
  String? _selectedCountry;
  String? _selectedState;
  bool _loadingCountries = true;
  bool _loadingStates = false;
  bool _isUpdating = false; 
  final String _apiKey = 'ZWh4b3h0TXZCTk41akhlUEJyQ3pXVExyMUxRZkNUVDdNRzh0ZTVHRA==';

  @override void initState() { 
    super.initState(); 
    _initData(); 
  }

  Future<void> _initData() async {
    await _loadCountries();
    await _loadUserData();
  }

  Future<void> _loadCountries() async {
    if (!mounted) return;
    setState(() => _loadingCountries = true);
    try {
      final response = await http.get(
        Uri.parse('https://api.countrystatecity.in/v1/countries'), 
        headers: {'X-CSCAPI-KEY': _apiKey}
      );
      if(response.statusCode==200) {
        final list = json.decode(response.body) as List;
        if (mounted) {
          setState(() {
            _countries = list.map((c) => {'name': c['name'], 'iso2': c['iso2']}).toList();
            _countries.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
            _loadingCountries = false;
          });
          // Intentar restaurar si el país ya estaba guardado en user data
          if (_selectedCountry != null) _loadStates(_getCountryCode(_selectedCountry!)!);
        }
      } else {
        if(mounted) setState(() => _loadingCountries = false);
      }
    } catch(e) { 
      debugPrint("Error Countries: $e"); 
      if(mounted) setState(() => _loadingCountries = false);
    }
  }

  Future<void> _loadStates(String countryCode) async {
    setState(() { _loadingStates = true; _selectedState=null; _states=[]; });
    try {
      final res = await http.get(
        Uri.parse('https://api.countrystatecity.in/v1/countries/$countryCode/states'), 
        headers: {'X-CSCAPI-KEY': _apiKey}
      );
      if(res.statusCode==200) {
        final list = json.decode(res.body) as List;
        if (mounted) {
          setState(() {
            _states = list.map((s) => s['name'].toString()).toList()..sort();
            _loadingStates = false;
          });
          // Si teníamos un estado pendiente por restaurar, lo asignamos
          if (_pendingState != null && _states.contains(_pendingState)) {
            setState(() => _selectedState = _pendingState);
            _pendingState = null; // Limpiar pendiente
          }
        }
      }
    } catch(e) { 
      debugPrint("Error States: $e"); 
      if (mounted) setState(() => _loadingStates = false);
    }
  }

  String? _getCountryCode(String name) {
    try {
      return _countries.firstWhere((c) => c['name'] == name)['iso2'];
    } catch (e) { return null; }
  }

  String? _pendingState; // Variable temporal para guardar estado mientras cargan los datos

  Future<void> _loadUserData() async {
    final u = FirebaseAuth.instance.currentUser; if(u==null)return;
    _emailCtrl.text = u.email ?? '';
    try {
      final d = await FirebaseFirestore.instance.collection('usuarios').doc(u.uid).get();
      if(d.exists && mounted) {
        final data = d.data() as Map<String, dynamic>;
        _nameCtrl.text = data['nombre']?.toString() ?? '';
        _birthCtrl.text = data['cumpleaños']?.toString() ?? '';
        
        String telfDb = data['telefono']?.toString() ?? '';
        if(telfDb.startsWith("58")) { telfDb = "0${telfDb.substring(2)}"; }
        _phoneCtrl.text = telfDb; 
        
        String? pais = data['pais']?.toString();
        String? estado = data['estado/ciudad']?.toString();
        
        if(pais != null && pais.isNotEmpty) {
          // Si la lista de países ya cargó
          if(_countries.isNotEmpty) {
             setState(() => _selectedCountry = pais);
             final code = _getCountryCode(pais);
             if(code != null) {
               _pendingState = estado; // Guardamos estado para cuando cargue la lista
               _loadStates(code);
             }
          } else {
             // Si no ha cargado, lo asignamos y dejamos que _loadCountries se encargue (menos ideal, pero cubrimos caso)
             _selectedCountry = pais;
             _pendingState = estado;
          }
        }
      }
    } catch (e) { debugPrint("Error user data: $e"); }
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(backgroundColor: Colors.transparent, title: const Text("Editar Perfil", style: TextStyle(color: Colors.white)), iconTheme: const IconThemeData(color: Colors.white)),
      body: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("Datos Personales", style: TextStyle(color: Color(0xFF11D7A1), fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 15),
        Form(key: _formKey, child: Column(children: [
          _input(_nameCtrl, "Nombre Completo", Icons.person, (v)=>v!.isEmpty?"Requerido":null), const SizedBox(height: 10),
          _input(_emailCtrl, "Correo", Icons.email, (v)=>v!.contains('@')?null:"Correo inválido"), const SizedBox(height: 10),
          
          _input(_phoneCtrl, "Teléfono (Ej: 0412...)", Icons.phone, (v) {
            if(v==null || v.isEmpty) return "Requerido";
            if(!RegExp(r'^04[0-9]{9}$').hasMatch(v)) return "Debe ser 04... y tener 11 dígitos";
            return null;
          }), const SizedBox(height: 10),
          
          GestureDetector(onTap: _pickBirthDate, child: AbsorbPointer(child: _input(_birthCtrl, "Fecha Nacimiento", Icons.cake, (v)=>v!.isEmpty?"Requerido":null))), const SizedBox(height: 10),
          
          _loadingCountries 
            ? const Padding(padding: EdgeInsets.all(8.0), child: LinearProgressIndicator(color: Color(0xFF11D7A1))) 
            : DropdownButtonFormField<String>(
                value: _selectedCountry, 
                dropdownColor: const Color(0xFF2C2C2C), 
                style: const TextStyle(color: Colors.white), 
                decoration: _dec("País", Icons.public), 
                items: _countries.map((c)=>DropdownMenuItem(
                  value: c['name'] as String, 
                  child: Row(children: [
                    if(c['iso2']!=null) 
                      Image.network('https://flagcdn.com/w40/${c['iso2'].toString().toLowerCase()}.png', width: 24, errorBuilder: (c,e,s)=>const Icon(Icons.flag, size: 20)), 
                    const SizedBox(width: 10), 
                    Flexible(child: Text(c['name'], overflow: TextOverflow.ellipsis))
                  ])
                )).toList(), 
                onChanged: (v) { 
                  setState(() => _selectedCountry = v); 
                  if(v!=null) {
                    final code = _getCountryCode(v);
                    if (code != null) _loadStates(code);
                  }
                }
              ),
          const SizedBox(height: 10),
          
          if(_loadingStates) const LinearProgressIndicator(color: Color(0xFF11D7A1)) else DropdownButtonFormField<String>(
            value: _selectedState, 
            dropdownColor: const Color(0xFF2C2C2C), 
            style: const TextStyle(color: Colors.white), 
            decoration: _dec("Estado", Icons.map), 
            items: _states.map((s)=>DropdownMenuItem(value: s, child: Text(s))).toList(), 
            onChanged: (v)=>setState(()=>_selectedState=v)
          ),
          
          const SizedBox(height: 20),
          
          SizedBox(
            width: double.infinity, 
            child: ElevatedButton(
              onPressed: _isUpdating ? null : _updateData, 
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF11D7A1)), 
              child: _isUpdating 
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) 
                : const Text("Actualizar Datos", style: TextStyle(color: Colors.black))
            )
          )
        ])),
        const SizedBox(height: 30),
        const Divider(color: Colors.white24),
        const SizedBox(height: 10),
        const Text("Seguridad", style: TextStyle(color: Color(0xFFEF476F), fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 15),
        Form(key: _passKey, child: Column(children: [
          _input(_oldPass, "Contraseña Actual", Icons.lock, (v)=>v!.isEmpty?"Requerido":null, pass: true), const SizedBox(height: 10),
          _input(_newPass, "Nueva Contraseña", Icons.lock_outline, (v)=>v!.length<6?"Mínimo 6 caracteres":null, pass: true), const SizedBox(height: 10),
          _input(_repPass, "Repetir Nueva", Icons.lock_outline, (v)=>v!=_newPass.text?"No coinciden":null, pass: true), const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _updatePass, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF476F)), child: const Text("Cambiar Contraseña", style: TextStyle(color: Colors.white))))
        ]))
      ]))
    );
  }
  
  InputDecoration _dec(String l, IconData i) => InputDecoration(labelText: l, labelStyle: const TextStyle(color: Colors.white54), prefixIcon: Icon(i, color: Colors.white54), filled: true, fillColor: const Color(0xFF1E1E1E), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)));
  Widget _input(TextEditingController c, String l, IconData i, String? Function(String?)? val, {bool pass=false}) => TextFormField(controller: c, obscureText: pass, style: const TextStyle(color: Colors.white), decoration: _dec(l, i), validator: val);

  Future<void> _pickBirthDate() async {
    final d = await showDatePicker(context: context, initialDate: DateTime(2000), firstDate: DateTime(1900), lastDate: DateTime.now());
    if(d!=null) {
      final age = DateTime.now().year - d.year;
      if (age < 10) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Debes tener al menos 10 años."), backgroundColor: Colors.red)); return; }
      _birthCtrl.text = DateFormat('dd/MM/yyyy').format(d);
    }
  }

  Future<void> _updateData() async {
    if(!_formKey.currentState!.validate()) return;
    final u = FirebaseAuth.instance.currentUser; if(u==null)return;
    
    setState(() => _isUpdating = true); 

    try {
      if(u.email != _emailCtrl.text && _emailCtrl.text.isNotEmpty) {
        await u.verifyBeforeUpdateEmail(_emailCtrl.text); 
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Verifica tu nuevo correo"), backgroundColor: Colors.orange)); 
      }
      
      String rawPhone = _phoneCtrl.text.trim();
      String finalPhone = rawPhone;
      if (rawPhone.startsWith('0')) {
        finalPhone = "58${rawPhone.substring(1)}";
      }

      await FirebaseFirestore.instance.collection('usuarios').doc(u.uid).update({
        'nombre': _nameCtrl.text, 
        'cumpleaños': _birthCtrl.text,
        'telefono': finalPhone, 
        'pais': _selectedCountry, 
        FieldPath(const ['estado/ciudad']): _selectedState
      });
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Datos actualizados"), backgroundColor: Color(0xFF11D7A1)));
    } catch(e) { 
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red)); 
    } finally {
      if(mounted) setState(() => _isUpdating = false); 
    }
  }
  
  Future<void> _updatePass() async {
    if(!_passKey.currentState!.validate()) return;
    try {
      final u = FirebaseAuth.instance.currentUser;
      final cred = EmailAuthProvider.credential(email: u!.email!, password: _oldPass.text);
      await u.reauthenticateWithCredential(cred);
      await u.updatePassword(_newPass.text);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Contraseña cambiada"), backgroundColor: Color(0xFF11D7A1)));
      _oldPass.clear(); _newPass.clear(); _repPass.clear();
    } catch(e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: Verifique su contraseña actual"), backgroundColor: Colors.red)); }
  }
}

// --- SOBRE NOSOTROS ---
class AboutUsScreen extends StatelessWidget {
  const AboutUsScreen({super.key});
  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(backgroundColor: Colors.transparent, iconTheme: const IconThemeData(color: Colors.white)),
      body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.code, size: 60, color: Color(0xFF11D7A1)),
        const SizedBox(height: 20),
        const Text("Desarrolladores", style: TextStyle(fontSize: 30, color: Colors.white, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        const Text("El equipo detrás de Easier Agenda", style: TextStyle(color: Colors.white54)),
        const SizedBox(height: 40),
        _dev("Carlos Luna", "carlosluna1611@gmail.com", "+58 412-4671498"),
        const SizedBox(height: 20),
        _dev("Kevin Montilla", "mon.kevinfernando09@gmail.com", "+58 412-4028015")
      ])))
    );
  }
  Widget _dev(String n, String e, String p) => Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white12)), child: Row(children: [
    CircleAvatar(radius: 25, backgroundColor: const Color(0xFF26547C), child: Text(n[0], style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white))),
    const SizedBox(width: 15),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(n, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)), Text(e, style: const TextStyle(color: Colors.white54, fontSize: 12)), Text(p, style: const TextStyle(color: Color(0xFF11D7A1), fontSize: 12))]))
  ]));
}