#!/usr/bin/env python3
"""Overlay only the signed companion onto both pinned user baselines."""
import copy
import gzip
import hashlib
import io
import lzma
import re
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION = "3.0-beta6"
BASELINES = (
    ("arm64", "var/jb/", "5f2f16b17281d0d3cbf9eb2bd096a7021e176261023c21d9d8f892f9a3141cfb"),
    ("arm64e", "", "483130e2bc6ee885845bb66b0b9e183aa66f4f54b6bb1a950c9935f0e473a7f5"),
)
XZ_FILTERS = [{"id": lzma.FILTER_LZMA2, "preset": 9 | lzma.PRESET_EXTREME,
               "dict_size": 32 * 1024 * 1024}]
SLIM_REMOVE_SUFFIXES = (".png", ".jpg", ".jpeg")


def slim_remove(name):
    return ("/Library/Application Support/ControlCenter18/Settings18/" in name or
            "/Library/Application Support/ControlCenter18/AVControls18.bundle/Mic Modes Visualizer.ca/" in name or
            "/Library/PreferenceBundles/ControlCenter18Prefs.bundle/" in name and
            name.lower().endswith(SLIM_REMOVE_SUFFIXES))


def deb_members(blob):
    assert blob[:8] == b"!<arch>\n", "Invalid ar header"
    offset, members = 8, {}
    while offset < len(blob):
        header = blob[offset:offset + 60]
        assert len(header) == 60 and header[58:] == b"`\n", "Invalid ar member"
        name = header[:16].decode("ascii").strip().rstrip("/")
        size = int(header[48:58])
        offset += 60
        assert size >= 0 and offset + size <= len(blob) and name not in members
        members[name] = blob[offset:offset + size]
        offset += size + size % 2
    assert offset == len(blob) and members.get("debian-binary") == b"2.0\n"
    assert len(members) == 3, "Expected a three-member deb"
    return members


def archive(blob):
    entries = {}
    with tarfile.open(fileobj=io.BytesIO(blob), mode="r:*") as tar:
        for info in tar:
            name = info.name.removeprefix("./")
            assert not name.startswith("/") and ".." not in Path(name).parts, name
            assert name not in entries, name
            content = tar.extractfile(info).read() if info.isfile() else None
            entries[name] = (copy.copy(info), content)
    return entries


def replace_content(entries, name, content):
    info = copy.copy(entries[name][0])
    assert info.isfile(), name
    info.size = len(content)
    entries[name] = (info, content)


def serialize(entries, compressed=False):
    """Keep original TarInfo; write directories before files and symlinks."""
    assert not any(info.islnk() for info, _ in entries.values()), "Unexpected hardlink"
    names = sorted(entries, key=lambda name: (
        not entries[name][0].isdir(),
        name.count("/") if entries[name][0].isdir() else 0,
        name,
    ))
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.USTAR_FORMAT) as tar:
        for name in names:
            info, content = entries[name]
            info = copy.copy(info)
            info.pax_headers = {}
            tar.addfile(info, io.BytesIO(content) if info.isfile() else None)
    raw = buf.getvalue()
    return gzip.compress(raw, compresslevel=9, mtime=0) if compressed else raw


def compress_data(raw):
    compressed = lzma.compress(raw, format=lzma.FORMAT_XZ,
                               check=lzma.CHECK_CRC64, filters=XZ_FILTERS)
    assert lzma.decompress(compressed, memlimit=40 * 1024 * 1024) == raw
    return compressed


def write_deb(path, control, data):
    members = (("debian-binary", b"2.0\n"),
               ("control.tar.gz", control), ("data.tar.xz", data))
    with path.open("wb") as out:
        out.write(b"!<arch>\n")
        for name, content in members:
            header = (f"{name + '/':<16}{0:<12}{0:<6}{0:<6}"
                      f"{'100644':<8}{len(content):<10}`\n").encode("ascii")
            assert len(header) == 60
            out.write(header)
            out.write(content)
            if len(content) % 2:
                out.write(b"\n")


def main():
    companion = (ROOT / "build/C18ConnectivityFive.dylib").read_bytes()
    assert companion, "Missing signed companion content"
    dist = ROOT / "dist"
    dist.mkdir(exist_ok=True)
    for arch, prefix, digest in BASELINES:
        baseline = (ROOT / f"Vendor/baseline-{arch}.deb").read_bytes()
        assert hashlib.sha256(baseline).hexdigest() == digest, f"Wrong {arch} baseline"
        members = deb_members(baseline)
        control_names = [name for name in members if name.startswith("control.tar")]
        data_names = [name for name in members if name.startswith("data.tar")]
        assert len(control_names) == len(data_names) == 1
        control, data = archive(members[control_names[0]]), archive(members[data_names[0]])
        original = dict(data)
        slim_removed = {name for name in data if slim_remove(name)}
        for name in slim_removed:
            del data[name]
        assert slim_removed, "Slimming rule removed nothing"
        folder = prefix + "Library/MobileSubstrate/DynamicLibraries/"
        target = folder + "C18ConnectivityFive.dylib"
        removed = {folder + "C18PowerMenu.dylib", folder + "C18PowerMenu.plist"}
        if arch == "arm64e":
            removed.add(folder + "C18PowerMenu.dylib.roothidepatch")
        assert target in data and removed <= data.keys(), "Missing baseline overlay paths"
        for name in removed:
            del data[name]
        replace_content(data, target, companion)
        assert data.keys() == original.keys() - removed - slim_removed
        assert all(data[name] == original[name] for name in data if name != target), "Overlay escaped companion scope"

        # Compute this only after all payload changes; preserve every other control byte.
        old_control = control["control"][1]
        fields = dict(line.split(b":", 1) for line in old_control.splitlines()
                      if b":" in line and not line.startswith((b" ", b"\t")))
        assert fields[b"Version"].strip() == VERSION.encode()
        assert fields[b"Architecture"].strip() == f"iphoneos-{arch}".encode()
        installed_size = (sum(len(content) for _, content in data.values()
                              if content is not None) + 1023) // 1024
        new_control, count = re.subn(br"(?m)^Installed-Size:[^\r\n]*",
                                    f"Installed-Size: {installed_size}".encode(), old_control)
        assert count == 1, "Expected exactly one Installed-Size field"
        replace_content(control, "control", new_control)
        out = dist / f"com.evgeniy558.controlcenter18_{VERSION}_iphoneos-{arch}.deb"
        write_deb(out, serialize(control, compressed=True), compress_data(serialize(data)))
        print(out.relative_to(ROOT), out.stat().st_size, hashlib.sha256(out.read_bytes()).hexdigest())


if __name__ == "__main__":
    main()
