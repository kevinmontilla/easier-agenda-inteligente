import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _userCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  final TextEditingController _confPassCtrl = TextEditingController();
  final TextEditingController _birthCtrl = TextEditingController();

  String? _selectedCountry;
  String? _selectedState;
  String? _selectedSex;
  List<String> _availableStates = [];
  bool _isLoading = false;
  bool _loadingCountries = false;
  bool _loadingStates = false;
  List<Map<String, dynamic>> _countries = [];
  final List<String> _sexOptions = ['Hombre', 'Mujer', 'Prefiero no decirlo'];
  final String _apiKey = 'ZWh4b3h0TXZCTk41akhlUEJyQ3pXVExyMUxRZkNUVDdNRzh0ZTVHRA==';

  @override
  void initState() {
    super.initState();
    _loadCountries();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _userCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    _confPassCtrl.dispose();
    _birthCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCountries() async {
    if (!mounted) return;
    setState(() => _loadingCountries = true);
    try {
      final response = await http.get(Uri.parse('https://api.countrystatecity.in/v1/countries'), headers: {'X-CSCAPI-KEY': _apiKey});
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _countries = data.map((c) => {'name': c['name'], 'iso2': c['iso2']}).toList();
            _countries.sort((a, b) => a['name'].compareTo(b['name']));
          });
        }
      }
    } catch (e) {
      debugPrint('Error cargando países: $e');
    } finally {
      if (mounted) setState(() => _loadingCountries = false);
    }
  }

  Future<void> _loadStates(String code) async {
    setState(() { _loadingStates = true; _selectedState = null; _availableStates = []; });
    try {
      final response = await http.get(Uri.parse('https://api.countrystatecity.in/v1/countries/$code/states'), headers: {'X-CSCAPI-KEY': _apiKey});
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _availableStates = data.map((s) => s['name'] as String).toList()..sort();
          });
        }
      }
    } catch (e) {
      debugPrint('Error cargando estados: $e');
    } finally {
      if (mounted) setState(() => _loadingStates = false);
    }
  }

  String? _getCountryCode(String name) {
    try {
      return _countries.firstWhere((c) => c['name'] == name)['iso2'];
    } catch (e) {
      return null;
    }
  }

  bool _isAtLeast10YearsOld(DateTime date) {
    final now = DateTime.now();
    final age = now.year - date.year;
    if (now.month < date.month || (now.month == date.month && now.day < date.day)) return age - 1 >= 10;
    return age >= 10;
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (_birthCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ingresa tu fecha de nacimiento"), backgroundColor: Colors.red));
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Transformar Teléfono (0412... -> 58412...)
      String rawPhone = _phoneCtrl.text.trim();
      String finalPhone = rawPhone;
      if (rawPhone.startsWith('0')) {
        finalPhone = "58${rawPhone.substring(1)}";
      }

      // 2. Crear usuario en Auth
      final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text.trim(),
      );

      final uid = userCredential.user!.uid;

      // 3. Crear documento en Firestore (Estructura Solicitada)
      // Se usa la colección "usuarios" directamente como en home.dart
      await FirebaseFirestore.instance.collection('usuarios').doc(uid).set({
        'nombre': _nameCtrl.text.trim(),
        'username': _userCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'telefono': finalPhone, // Se guarda el número transformado (58...)
        'cumpleaños': _birthCtrl.text.trim(),
        'pais': _selectedCountry ?? '',
        'estado/ciudad': _selectedState ?? '',
        'genero': _selectedSex ?? '',
        'rachaActual': 0,
        'ultimoAcceso': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        // Campos de estado de la app
        'programaActual': '', 
        'materiaSeleccionada': '',
        'pendingAction': '', // Campo solicitado anteriormente
        'profileColor': 0xFF26547C, // Color por defecto
      });

      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/home', (r) => false);
      }
    } on FirebaseAuthException catch (e) {
      String msg = 'Error al registrarse';
      if (e.code == 'email-already-in-use') msg = 'El correo ya está registrado';
      if (e.code == 'weak-password') msg = 'La contraseña es muy débil';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      appBar: AppBar(
        title: const Text('Crear Cuenta'), 
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Únete a Easier', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                const SizedBox(height: 32),
                
                _buildTextField(_nameCtrl, 'Nombre completo', Icons.person),
                const SizedBox(height: 16),
                _buildTextField(_userCtrl, 'Usuario', Icons.alternate_email),
                const SizedBox(height: 16),
                _buildTextField(_emailCtrl, 'Correo', Icons.email, keyboardType: TextInputType.emailAddress),
                const SizedBox(height: 16),
                
                // CAMPO TELÉFONO CON VALIDACIÓN
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                  decoration: _friendlyDecoration('Teléfono (Ej: 0412...)', Icons.phone),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Requerido';
                    // Regex: Empieza por 0 y tiene 10 dígitos más (Total 11)
                    final RegExp phoneRegex = RegExp(r'^0[0-9]{10}$');
                    if (!phoneRegex.hasMatch(value)) {
                      return 'Debe tener 11 dígitos y empezar por 0';
                    }
                    return null;
                  },
                ),
                
                const SizedBox(height: 16),
                _buildTextField(_passCtrl, 'Contraseña', Icons.lock, isPass: true),
                const SizedBox(height: 16),
                
                TextFormField(
                  controller: _confPassCtrl,
                  obscureText: true,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                  decoration: _friendlyDecoration('Confirmar Contraseña', Icons.lock_outline),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Por favor confirma tu contraseña';
                    if (value != _passCtrl.text) return 'Las contraseñas no coinciden';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                
                // Selector de Género
                DropdownButtonFormField<String>(
                  value: _selectedSex,
                  items: _sexOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (v) => setState(() => _selectedSex = v),
                  decoration: _friendlyDecoration('Género', Icons.person_outline),
                  validator: (v) => v == null ? 'Requerido' : null,
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _birthCtrl,
                  readOnly: true,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                  decoration: _friendlyDecoration('Fecha de nacimiento', Icons.cake),
                  onTap: () async {
                    DateTime? date = await showDatePicker(
                      context: context, 
                      initialDate: DateTime(2005), 
                      firstDate: DateTime(1900), 
                      lastDate: DateTime.now(),
                    );
                    if (date != null) {
                      if(_isAtLeast10YearsOld(date)) {
                        _birthCtrl.text = "${date.day}/${date.month}/${date.year}";
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Debes tener al menos 10 años."), backgroundColor: Colors.red));
                      }
                    }
                  },
                ),
                const SizedBox(height: 16),
                
                _loadingCountries 
                  ? const Center(child: CircularProgressIndicator()) 
                  : DropdownButtonFormField<String>(
                      value: _selectedCountry,
                      isExpanded: true,
                      items: _countries.map((c) => DropdownMenuItem(
                        value: c['name'] as String,
                        child: Row(
                          children: [
                            if (c['iso2'] != null)
                              Image.network(
                                'https://flagcdn.com/w40/${c['iso2'].toString().toLowerCase()}.png',
                                width: 24,
                                errorBuilder: (c,e,s) => const Icon(Icons.flag, size: 20),
                              ),
                            const SizedBox(width: 10),
                            Flexible(child: Text(c['name'], overflow: TextOverflow.ellipsis))
                          ],
                        )
                      )).toList(),
                      onChanged: (v) { 
                        setState(() => _selectedCountry = v); 
                        if(v != null) { 
                          final code = _getCountryCode(v); 
                          if(code != null) _loadStates(code); 
                        } 
                      },
                      decoration: _friendlyDecoration('País', Icons.public),
                    ),
                const SizedBox(height: 16),
                
                if (_selectedCountry != null)
                  _loadingStates 
                    ? const Center(child: CircularProgressIndicator()) 
                    : DropdownButtonFormField<String>(
                        value: _selectedState,
                        isExpanded: true,
                        items: _availableStates.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))).toList(),
                        onChanged: (v) => setState(() => _selectedState = v),
                        decoration: _friendlyDecoration('Estado/Ciudad', Icons.map),
                      ),

                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _register,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 4,
                    ),
                    child: _isLoading 
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                      : const Text('Registrarse', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ),
                
                const SizedBox(height: 20),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("¿Ya tienes una cuenta? ", style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                    GestureDetector(
                      onTap: () => Navigator.pushReplacementNamed(context, '/login'),
                      child: Text("Inicia Sesión", style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _friendlyDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: Theme.of(context).colorScheme.primary),
      filled: true,
      fillColor: Theme.of(context).colorScheme.surface,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Theme.of(context).colorScheme.primary.withOpacity(0.2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.red),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String label, IconData icon, {bool isPass = false, TextInputType? keyboardType}) {
    return TextFormField(
      controller: ctrl,
      obscureText: isPass,
      keyboardType: keyboardType,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
      decoration: _friendlyDecoration(label, icon),
      validator: (v) => v!.isEmpty ? 'Requerido' : null,
    );
  }
}