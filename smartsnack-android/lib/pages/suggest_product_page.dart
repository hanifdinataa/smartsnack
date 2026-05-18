import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../providers/app_providers.dart';

class SuggestProductPage extends ConsumerStatefulWidget {
  const SuggestProductPage({super.key});

  @override
  ConsumerState<SuggestProductPage> createState() => _SuggestProductPageState();
}

class _SuggestProductPageState extends ConsumerState<SuggestProductPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _grSugar = TextEditingController();
  final _netWeight = TextEditingController();
  final _servings = TextEditingController();
  final _servingVol = TextEditingController();

  String _category = 'drink';
  XFile? _image;
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _grSugar.dispose();
    _netWeight.dispose();
    _servings.dispose();
    _servingVol.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85);
    if (picked != null) {
      setState(() => _image = picked);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_image == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Silakan ambil gambar terlebih dahulu')));
      return;
    }

    setState(() => _loading = true);
    try {
      await ref.read(apiServiceProvider).suggestProduct(
            name: _name.text.trim(),
            category: _category,
            grSugarContent: double.parse(_grSugar.text),
            netWeight: double.parse(_netWeight.text),
            servingsPerPackage: double.parse(_servings.text),
            servingSizeMl: double.parse(_servingVol.text),
            imageFile: _image!,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Berhasil mengirimkan data produk')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saran Produk Baru')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nama Produk'),
                validator: (value) => value == null || value.trim().isEmpty ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _category,
                items: const [
                  DropdownMenuItem(value: 'drink', child: Text('Drink')),
                  DropdownMenuItem(value: 'food', child: Text('Food')),
                ],
                onChanged: (value) => setState(() => _category = value ?? 'drink'),
                decoration: const InputDecoration(labelText: 'Kategori Produk'),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _grSugar,
                decoration: const InputDecoration(labelText: 'Gula/Sajian'),
                keyboardType: TextInputType.number,
                validator: (value) => value == null || double.tryParse(value) == null ? 'Harus angka' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _netWeight,
                decoration: const InputDecoration(labelText: 'Berat Bersih'),
                keyboardType: TextInputType.number,
                validator: (value) => value == null || double.tryParse(value) == null ? 'Harus angka' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _servings,
                decoration: const InputDecoration(labelText: 'Jumlah Sajian'),
                keyboardType: TextInputType.number,
                validator: (value) => value == null || double.tryParse(value) == null ? 'Harus angka' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _servingVol,
                decoration: const InputDecoration(labelText: 'Volume/Sajian'),
                keyboardType: TextInputType.number,
                validator: (value) => value == null || double.tryParse(value) == null ? 'Harus angka' : null,
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickImage,
                child: Container(
                  width: double.infinity,
                  height: 180,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black26),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _image == null
                      ? const Center(child: Text('Tambahkan Gambar Produk'))
                      : FutureBuilder<Uint8List>(
                          future: _image!.readAsBytes(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.memory(snapshot.data!, fit: BoxFit.cover),
                            );
                          },
                        ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Kirim'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
