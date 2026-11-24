#!/usr/bin/env python3
"""Downloads files from a PUBLIC MEGA folder link (HTTPS only).

Usage:
    python3 -I tools/assets/fetch_mega_folder.py <folder_url> <out_dir> [--only a.zip,b.zip] [--list]

* The folder link (including its #key) is a secret: pass it via an
  environment variable / CI secret, never commit it.
* Files are written flat into <out_dir> by their file name; names are
  sanitised, so remote paths can never escape <out_dir>.
* Decryption follows MEGA's public scheme (AES-ECB node keys, AES-CBC
  attributes, AES-CTR file data). Downloads always use HTTPS URLs ("ssl": 2).

Requires: requests, cryptography.
"""
import base64
import json
import os
import struct
import sys
import time

import requests
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

API = "https://g.api.mega.co.nz/cs"


def b64d(s):
    s = s.replace("-", "+").replace("_", "/").replace(",", "")
    return base64.b64decode(s + "=" * (-len(s) % 4))


def aes(mode, key, data):
    d = Cipher(algorithms.AES(key), mode).decryptor()
    return d.update(data) + d.finalize()


def api(folder_handle, payload, _seq=[0]):
    _seq[0] += 1
    for attempt in range(7):
        r = requests.post(API, params={"id": _seq[0], "n": folder_handle}, data=json.dumps([payload]), timeout=60)
        res = r.json()
        res = res[0] if isinstance(res, list) else res
        if res == -3:  # EAGAIN: server busy
            time.sleep(2 ** attempt)
            continue
        if isinstance(res, int) and res < 0:
            raise RuntimeError(f"MEGA API error {res}")
        return res
    raise RuntimeError("MEGA API busy")


def safe_name(name):
    name = os.path.basename(name.replace("\\", "/")).strip()
    return "_" if name in ("", ".", "..") else name


def list_files(url):
    part = url.split("/folder/", 1)[1]
    handle = part.split("#", 1)[0]
    master = b64d(part.split("#", 1)[1].split("/")[0])
    res = api(handle, {"a": "f", "c": 1, "r": 1, "ca": 1})
    folders = {n["h"] for n in res["f"] if n["t"] == 1}
    files = []
    for n in res["f"]:
        if n["t"] != 0 or ":" not in n.get("k", ""):
            continue
        # A node can carry several "owner:key" entries; use the one belonging
        # to a folder of this share (encrypted with the share key).
        entries = [e.split(":", 1) for e in n["k"].split("/") if ":" in e]
        chosen = next((e for e in entries if e[0] in folders), entries[0])
        raw = aes(modes.ECB(), master, b64d(chosen[1]))
        a = struct.unpack(">8I", raw[:32])
        key = struct.pack(">4I", a[0] ^ a[4], a[1] ^ a[5], a[2] ^ a[6], a[3] ^ a[7])
        attr = aes(modes.CBC(b"\0" * 16), key, b64d(n["a"])).rstrip(b"\0")
        meta = json.loads(attr[4:].decode("utf-8", "replace")) if attr.startswith(b"MEGA") else {}
        files.append({"h": n["h"], "name": safe_name(meta.get("n", n["h"])), "size": n.get("s", 0),
                      "key": key, "iv": raw[16:24]})
    return handle, files


def download(handle, f, out_dir):
    dest = os.path.join(out_dir, f["name"])
    if os.path.exists(dest) and os.path.getsize(dest) == f["size"]:
        return dest
    link = api(handle, {"a": "g", "g": 1, "n": f["h"], "ssl": 2})["g"]
    if link.startswith("http://"):
        link = "https://" + link[len("http://"):]
    ctr = Cipher(algorithms.AES(f["key"]), modes.CTR(f["iv"] + b"\0" * 8)).decryptor()
    tmp = dest + ".part"
    with requests.get(link, stream=True, timeout=300) as r, open(tmp, "wb") as fh:
        r.raise_for_status()
        for chunk in r.iter_content(1 << 20):
            fh.write(ctr.update(chunk))
        fh.write(ctr.finalize())
    if os.path.getsize(tmp) != f["size"]:
        raise RuntimeError(f"size mismatch for {f['name']}")
    os.replace(tmp, dest)
    return dest


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) < 2:
        print(__doc__)
        return 2
    url, out_dir = args[0], os.path.abspath(args[1])
    only = []
    if "--only" in sys.argv:
        only = sys.argv[sys.argv.index("--only") + 1].split(",")
    handle, files = list_files(url)
    if only:
        files = [f for f in files if f["name"] in only]
    print(f"{len(files)} file(s), {sum(f['size'] for f in files) / 1e6:.1f} MB")
    for f in files:
        print(f"  {f['size'] / 1e6:9.2f} MB  {f['name']}")
    if "--list" in sys.argv:
        return 0
    os.makedirs(out_dir, exist_ok=True)
    for f in files:
        download(handle, f, out_dir)
        print(f"ok {f['name']}", flush=True)
    missing = [n for n in only if n not in {f["name"] for f in files}]
    if missing:
        print(f"not found in folder: {missing}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
