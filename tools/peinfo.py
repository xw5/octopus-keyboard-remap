"""Dump PE sections and the resource directory tree of an exe.

Usage: python -I peinfo.py <exe>
"""
import struct
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

IMAGE_RESOURCE_DIRECTORY = 0
RT_NAMES = {1: "CURSOR", 2: "BITMAP", 3: "ICON", 4: "MENU", 5: "DIALOG",
            6: "STRING", 7: "FONTDIR", 8: "FONT", 9: "ACCELERATOR",
            10: "RCDATA", 11: "MESSAGETABLE", 12: "GROUP_CURSOR",
            14: "GROUP_ICON", 16: "VERSION", 24: "MANIFEST"}


def main(path):
    data = open(path, "rb").read()
    e_lfanew = struct.unpack_from("<I", data, 0x3C)[0]
    assert data[e_lfanew:e_lfanew + 4] == b"PE\0\0", "not a PE file"
    coff = e_lfanew + 4
    nsec = struct.unpack_from("<H", data, coff + 2)[0]
    opt_size = struct.unpack_from("<H", data, coff + 16)[0]
    opt = coff + 20   # optional header follows the 20-byte COFF header
    magic = struct.unpack_from("<H", data, opt)[0]
    pe32plus = magic == 0x20B
    rva_rsrc = struct.unpack_from("<I", data, opt + (0x70 if pe32plus else 0x60) + 2 * 8)[0]
    sec0 = opt + opt_size
    print("sections:")
    secs = []
    for i in range(nsec):
        off = sec0 + i * 40
        name = data[off:off + 8].rstrip(b"\0").decode("ascii", "replace")
        vsize, vaddr, rsize, raddr = struct.unpack_from("<IIII", data, off + 8)
        flag = "  <-- .rsrc" if name == ".rsrc" else ""
        print("  %-8s vaddr=%#010x vsize=%#x raw=%#010x size=%#x%s"
              % (name, vaddr, vsize, raddr, rsize, flag))
        secs.append((name, vaddr, vsize, raddr, rsize))

    def rva_to_off(rva):
        for _, vaddr, vsize, raddr, rsize in secs:
            if vaddr <= rva < vaddr + max(vsize, rsize):
                return raddr + (rva - vaddr)
        return None

    def walk(off, level, path):
        nnamed, nid = struct.unpack_from("<HH", data, off + 12)
        for i in range(nnamed + nid):
            ent = off + 16 + i * 8
            name_rva, data_rva = struct.unpack_from("<II", data, ent)
            if name_rva & 0x80000000:
                noff = rva_to_off(name_rva & 0x7FFFFFFF)
                label = "name@%#x" % (name_rva & 0x7FFFFFFF)
                if noff is not None:
                    ln = struct.unpack_from("<H", data, noff)[0]
                    label = data[noff + 2:noff + 2 + ln].decode("utf-16-le")
            else:
                label = str(name_rva)
            if data_rva & 0x80000000:
                # subdirectory offsets are relative to the resource dir start
                walk(rsrc_off + (data_rva & 0x7FFFFFFF), level + 1,
                     path + [label])
            else:
                doff = rva_to_off(data_rva)
                if doff is None:
                    print("  res %-12s id=%-4s BROKEN data RVA %#x"
                          % (RT_NAMES.get(int(rt), rt), "/".join(path[1:]),
                             data_rva))
                    continue
                # IMAGE_RESOURCE_DATA_ENTRY: OffsetToData(RVA), Size, CodePage
                drva = struct.unpack_from("<I", data, doff)[0]
                dsize = struct.unpack_from("<I", data, doff + 4)[0]
                dcodepage = struct.unpack_from("<I", data, doff + 8)[0]
                dptr = rva_to_off(drva)
                rt = path[0] if path[0].isdigit() else "?"
                print("  res %-12s id=%-4s size=%-8d codepage=%d dataRVA=%#x %s"
                      % (RT_NAMES.get(int(rt), rt), "/".join(path[1:]),
                         dsize, dcodepage, drva,
                         "" if dptr is not None else "UNMAPPED"))
                if path[0] == "24":
                    xml = data[dptr:dptr + dsize] if dptr else b""
                    print("      manifest[%d]: %r" % (dsize, xml[:120]))

    rsrc_off = rva_to_off(rva_rsrc)
    if rsrc_off is None:
        print("NO .rsrc directory")
        return
    print("resource tree (rsrc at file offset %#x):" % rsrc_off)
    walk(rsrc_off, 0, [])


main(sys.argv[1])
