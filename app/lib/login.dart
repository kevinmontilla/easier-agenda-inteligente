import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      appBar: AppBar(title: const Text('Iniciar Sesión'), centerTitle: true),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bienvenido de nuevo', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                const SizedBox(height: 8),
                Text('Ingresa a tu cuenta para continuar', style: TextStyle(fontSize: 18, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7))),
                const SizedBox(height: 40),
                _buildTextField(_emailController, 'Correo electrónico', Icons.email_outlined),
                const SizedBox(height: 20),
                _buildTextField(_passwordController, 'Contraseña', Icons.lock_outline, isObscure: true),
                const SizedBox(height: 30),
                SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _isLoading ? null : _login, style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: _isLoading ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Iniciar Sesión', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)))),
                const SizedBox(height: 20),
                Center(child: TextButton(onPressed: () => Navigator.pushNamed(context, '/register'), child: Text('¿No tienes cuenta? Regístrate aquí', style: TextStyle(color: Theme.of(context).colorScheme.secondary, fontSize: 16)))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String label, IconData icon, {bool isObscure = false}) {
    return TextFormField(
      controller: ctrl, obscureText: isObscure, style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, color: Theme.of(context).colorScheme.primary), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: Theme.of(context).colorScheme.surface),
      validator: (value) => value!.isEmpty ? 'Campo requerido' : null,
    );
  }

  void _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: _emailController.text.trim(), password: _passwordController.text.trim());
      if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
    } on FirebaseAuthException catch (e) {
      String message = 'Error desconocido';
      switch (e.code) {
        case 'user-not-found': message = 'No existe una cuenta con este correo.'; break;
        case 'wrong-password': message = 'La contraseña es incorrecta.'; break;
        case 'invalid-email': message = 'El formato del correo no es válido.'; break;
        case 'user-disabled': message = 'Esta cuenta ha sido deshabilitada.'; break;
        case 'too-many-requests': message = 'Demasiados intentos. Intenta más tarde.'; break;
        case 'invalid-credential': message = 'Credenciales inválidas. Verifica tus datos.'; break;
      }
      if (mounted) _showErrorSnackBar(message);
    } catch (e) { if (mounted) _showErrorSnackBar('Error de conexión: $e'); } 
    finally { if (mounted) setState(() => _isLoading = false); }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Row(children: [const Icon(Icons.error_outline, color: Colors.white), const SizedBox(width: 10), Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))]), backgroundColor: const Color(0xFFEF476F), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
  }
}