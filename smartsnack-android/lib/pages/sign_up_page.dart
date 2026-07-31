import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';

class SignUpPage extends ConsumerStatefulWidget {
  const SignUpPage({super.key});

  @override
  ConsumerState<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends ConsumerState<SignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordConf = TextEditingController();
  final _age = TextEditingController();
  String _selectedGender = 'Male';
  bool _obscure1 = true;
  bool _obscure2 = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _passwordConf.dispose();
    _age.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);

    ref.listen<SessionState>(sessionProvider, (previous, next) {
      if (next.error != null && next.error != previous?.error) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.error!)));
        ref.read(sessionProvider.notifier).clearError();
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFFFAFFFF),
      appBar: AppBar(
        title: const Text('Daftar Akun'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0D9F6E), Color(0xFF059669)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.child_care_rounded, size: 48, color: Colors.white),
                      SizedBox(height: 8),
                      Text(
                        'Data Anak',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Isi dengan lengkap untuk monitoring kesehatan',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // ─── Nama ───
                _buildSectionLabel('Informasi Akun', Icons.person_rounded),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _name,
                  decoration: _inputDecoration('Nama Lengkap Anak', Icons.badge_outlined),
                  textCapitalization: TextCapitalization.words,
                  validator: (value) => value == null || value.trim().isEmpty ? 'Nama wajib diisi' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  decoration: _inputDecoration('Email', Icons.email_outlined),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Email wajib diisi';
                    final ok = RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value);
                    if (!ok) return 'Format email tidak valid';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure1,
                  decoration: _inputDecoration('Password', Icons.lock_outline).copyWith(
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscure1 = !_obscure1),
                      icon: Icon(_obscure1 ? Icons.visibility_off : Icons.visibility),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Password wajib diisi';
                    if (value.length < 6) return 'Password minimal 6 karakter';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordConf,
                  obscureText: _obscure2,
                  decoration: _inputDecoration('Konfirmasi Password', Icons.lock_outline).copyWith(
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscure2 = !_obscure2),
                      icon: Icon(_obscure2 ? Icons.visibility_off : Icons.visibility),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Konfirmasi password wajib diisi';
                    if (value != _password.text) return 'Password tidak cocok';
                    return null;
                  },
                ),

                const SizedBox(height: 24),

                // ─── Data Profil Anak ───
                _buildSectionLabel('Profil Kesehatan', Icons.health_and_safety_outlined),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF6EE7B7)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF059669)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Umur dan jenis kelamin bisa diubah nanti di profil',
                          style: TextStyle(fontSize: 12, color: Color(0xFF065F46)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _age,
                  decoration: _inputDecoration('Umur Anak (tahun)', Icons.cake_outlined),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Umur wajib diisi';
                    final age = int.tryParse(value);
                    if (age == null || age < 1 || age > 18) return 'Umur harus antara 1–18 tahun';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedGender,
                  decoration: _inputDecoration('Jenis Kelamin', Icons.wc_outlined),
                  items: const [
                    DropdownMenuItem(value: 'Male',   child: Text('Laki-laki')),
                    DropdownMenuItem(value: 'Female', child: Text('Perempuan')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _selectedGender = value);
                  },
                  validator: (value) => value == null ? 'Jenis kelamin wajib dipilih' : null,
                ),

                const SizedBox(height: 32),

                // ─── Tombol Daftar ───
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0D9F6E),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: session.loading
                      ? null
                      : () async {
                          if (!_formKey.currentState!.validate()) return;
                          final ok = await ref.read(sessionProvider.notifier).signUp(
                                name: _name.text.trim(),
                                email: _email.text.trim(),
                                password: _password.text,
                                passwordConfirmation: _passwordConf.text,
                                age: int.parse(_age.text),
                                gender: _selectedGender,
                              );
                          if (ok && mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                  child: session.loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Daftar Sekarang', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Sudah punya akun? Masuk', style: TextStyle(color: Color(0xFF0D9F6E))),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF0D9F6E), width: 2)),
    );
  }

  Widget _buildSectionLabel(String label, IconData icon) {
    return Row(children: [
      Icon(icon, size: 18, color: const Color(0xFF0D9F6E)),
      const SizedBox(width: 8),
      Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF111827))),
    ]);
  }
}
