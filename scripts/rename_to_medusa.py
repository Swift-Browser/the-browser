#!/usr/bin/env python3
import os
import sys

def transform_name(name: str) -> str:
    return name.replace("ARDIA", "MEDUSA").replace("Ardia", "Medusa").replace("ardia", "medusa")

def rename_project_entries(root_dir: str):
    excluded_directories = {".git", "node_modules", ".build"}
    files_to_rename = []
    directories_to_rename = []

    for dirpath, dirnames, filenames in os.walk(root_dir, topdown=True):
        dirnames[:] = [d for d in dirnames if d not in excluded_directories]

        for filename in filenames:
            transformed = transform_name(filename)
            if transformed != filename:
                files_to_rename.append((dirpath, filename, transformed))

        for dirname in dirnames:
            transformed = transform_name(dirname)
            if transformed != dirname:
                directories_to_rename.append(os.path.join(dirpath, dirname))

    directories_to_rename.sort(key=lambda path: path.count(os.sep), reverse=True)

    for dirpath, old_name, new_name in files_to_rename:
        src = os.path.join(dirpath, old_name)
        dst = os.path.join(dirpath, new_name)
        if os.path.exists(dst):
            print(f"Skipping existing file destination: {dst}")
            continue
        os.rename(src, dst)
        print(f"Renamed file: {src} -> {dst}")

    for dirpath in directories_to_rename:
        parent = os.path.dirname(dirpath)
        base = os.path.basename(dirpath)
        new_base = transform_name(base)
        dst = os.path.join(parent, new_base)
        if os.path.exists(dst):
            print(f"Skipping existing directory destination: {dst}")
            continue
        os.rename(dirpath, dst)
        print(f"Renamed directory: {dirpath} -> {dst}")

if __name__ == "__main__":
    target_root = sys.argv[1] if len(sys.argv) > 1 else os.getcwd()
    rename_project_entries(os.path.abspath(target_root))
