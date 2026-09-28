#!/usr/bin/env python3

import os
import re
import struct
import subprocess
import sys
import tempfile

CAP_FLOAT64 = struct.pack("<II", 0x00020011, 10)


def has_fp64(path):
    with open(path, "rb") as f:
        return CAP_FLOAT64 in f.read(4096)


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def patch(src, dst):
    if not has_fp64(src):
        return 2, "no Float64 capability"

    dis = run(["spirv-dis", src])
    if dis.returncode != 0:
        return 1, "spirv-dis failed: " + dis.stderr.strip()[:200]

    text = dis.stdout

    m = re.search(r"^; Version: (\d+)\.(\d+)", text, re.M)
    env = f"spv{m.group(1)}.{m.group(2)}" if m else "spv1.3"

    dm = re.search(r"^\s*(%\S+) = OpTypeFloat 64\s*$", text, re.M)
    if not dm:
        return 1, "Float64 capability but no 64-bit float type found"

    dbl = dm.group(1)
    dbl_tok = re.escape(dbl) + r"(?![\w])"

    for line in text.splitlines():
        if re.search(dbl_tok, line) and "OpFConvert" in line:
            return 1, "uses OpFConvert with doubles (needs manual review)"
        if re.search(r"OpType(Vector|Matrix|Array|RuntimeArray|Pointer|Struct)\b.*" + dbl_tok, line):
            return 1, "double vector/array/struct type (needs manual review)"

    if re.search(r"OpConvert[FSU]To[FSU]\b.*" + dbl_tok, text):
        pass

    fm = re.search(r"^\s*(%\S+) = OpTypeFloat 32\s*$", text, re.M)

    if fm:
        flt = fm.group(1)
        text = re.sub(
            r"^\s*" + re.escape(dbl) + r" = OpTypeFloat 64\s*\n",
            "",
            text,
            flags=re.M,
        )
    else:
        flt = dbl
        text = re.sub(
            r"(" + re.escape(dbl) + r" = OpTypeFloat )64",
            r"\g<1>32",
            text,
        )

    if flt != dbl:
        text = re.sub(
            r"(= Op(?:Spec)?Constant )" + dbl_tok,
            r"\g<1>" + flt.replace("\\", r"\\"),
            text,
        )
        text = re.sub(
            dbl_tok,
            flt.replace("\\", r"\\"),
            text,
        )

    text = re.sub(
        r"^\s*OpCapability Float64\s*\n",
        "",
        text,
        flags=re.M,
    )

    text = re.sub(
        r"^\s*OpExecutionMode \S+ (DenormPreserve|DenormFlushToZero|SignedZeroInfNanPreserve|"
        r"RoundingModeRTE|RoundingModeRTZ) 64\s*\n",
        "",
        text,
        flags=re.M,
    )

    with tempfile.TemporaryDirectory() as td:
        asm = os.path.join(td, "p.spvasm")
        out = os.path.join(td, "p.spv")

        with open(asm, "w") as f:
            f.write(text)

        a = run([
            "spirv-as",
            "--target-env",
            env,
            asm,
            "-o",
            out,
        ])

        if a.returncode != 0:
            return 1, "spirv-as failed: " + a.stderr.strip()[:200]

        v = run([
            "spirv-val",
            "--target-env",
            env,
            out,
        ])

        if v.returncode != 0:
            return 1, "patched shader failed validation: " + v.stderr.strip().splitlines()[0][:200]

        if has_fp64(out):
            return 1, "Float64 capability still present after patch"

        with open(out, "rb") as f, open(dst, "wb") as g:
            g.write(f.read())

    return 0, "ok"


def main(argv):
    if len(argv) == 4 and argv[1] == "patch":
        rc, msg = patch(argv[2], argv[3])
        print(msg)
        return rc

    if len(argv) == 4 and argv[1] == "scan":
        dump, out = argv[2], argv[3]
        os.makedirs(out, exist_ok=True)

        done = 0
        failed = 0

        for name in sorted(os.listdir(dump)):
            if not name.endswith(".spv"):
                continue

            src = os.path.join(dump, name)
            dst = os.path.join(out, name)

            if os.path.exists(dst) or not has_fp64(src):
                continue

            rc, msg = patch(src, dst)

            if rc == 0:
                done += 1
                print(f"  patched {name}")
            else:
                failed += 1
                print(f"  FAILED  {name}: {msg}")

        print(f"scan: {done} patched, {failed} failed")
        return 1 if failed else 0

    print(
        "Usage:\n"
        "  patcher.py patch IN.spv OUT.spv\n"
        "  patcher.py scan DUMP_DIR OUT_DIR"
    )
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))