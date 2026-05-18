import os
import re

# Path folder gambar
folder_path = "./"

# Cek apakah folder ada
if not os.path.exists(folder_path):
    print("Folder tidak ditemukan!")
    exit()

# Loop semua file dalam folder
for filename in os.listdir(folder_path):
    old_path = os.path.join(folder_path, filename)

    # Pastikan hanya file, bukan folder
    if os.path.isfile(old_path):
        name, ext = os.path.splitext(filename)

        # Hapus angka di depan + underscore setelah angka
        cleaned_name = re.sub(r'^\d+_', '', name)

        # Ganti underscore menjadi spasi
        cleaned_name = cleaned_name.replace('_', ' ')

        # Rapikan spasi berlebih
        cleaned_name = re.sub(r'\s+', ' ', cleaned_name).strip()

        # Gabungkan kembali dengan extension
        new_filename = cleaned_name + ext
        new_path = os.path.join(folder_path, new_filename)

        # Rename file
        os.rename(old_path, new_path)

        print(f"Renamed: {filename} -> {new_filename}")

print("\nSelesai rename semua file.")