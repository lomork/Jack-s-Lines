import 'package:flutter/material.dart';
import '../../database/auth_service.dart';
import '../menu/menu_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _auth = AuthService();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final TextEditingController _handleController = TextEditingController();

  bool isLoginMode = true;
  bool isLoading = false;

  void _handleAuth(String type) async {
    setState(() => isLoading = true);
    dynamic user;

    if (type == 'Google') {
      user = await _auth.signInWithGoogle();
    } else if (type == 'Guest') {
      user = await _auth.signInGuest();
    } else if (type == 'Login') {
      user = await _auth.login(_emailController.text.trim(), _passController.text.trim());
    } else {
      user = await _auth.register(_emailController.text.trim(), _passController.text.trim(), _handleController.text.trim());
    }

    if (!mounted) return;
    setState(() => isLoading = false);

    if (user != null) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MenuScreen()));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Authentication Failed"), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.hub, size: 80, color: Color(0xFFFFD700)),
              const SizedBox(height: 10),
              const Text("JACK'S LINES", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 2)),
              const SizedBox(height: 40),

              if (!isLoginMode)
                _buildTextField(_handleController, "Unique Handle (@username)", Icons.person),

              const SizedBox(height: 15),
              _buildTextField(_emailController, "Email Address", Icons.email),
              const SizedBox(height: 15),
              _buildTextField(_passController, "Password", Icons.lock, isObscure: true),

              const SizedBox(height: 30),

              if (isLoading) const CircularProgressIndicator() else Column(
                children: [
                  // MAIN EMAIL BUTTON
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700), padding: const EdgeInsets.symmetric(vertical: 15)),
                      onPressed: () => _handleAuth(isLoginMode ? 'Login' : 'SignUp'),
                      child: Text(isLoginMode ? "LOGIN" : "CREATE ACCOUNT", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),

                  const SizedBox(height: 15),

                  // GOOGLE BUTTON (NEW)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.g_mobiledata, color: Colors.black, size: 30),
                      label: const Text("Sign in with Google", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                      onPressed: () => _handleAuth('Google'),
                    ),
                  ),

                  const SizedBox(height: 15),

                  // GUEST BUTTON
                  TextButton(
                    onPressed: () => _handleAuth('Guest'),
                    child: const Text("Continue as Guest", style: TextStyle(color: Colors.grey)),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              TextButton(
                onPressed: () => setState(() => isLoginMode = !isLoginMode),
                child: Text(isLoginMode ? "New here? Create Account" : "Already have an account? Login", style: const TextStyle(color: Colors.blueAccent)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, IconData icon, {bool isObscure = false}) {
    return TextField(
      controller: controller,
      obscureText: isObscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: Colors.grey),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.grey),
        filled: true,
        fillColor: Colors.white10,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      ),
    );
  }
}