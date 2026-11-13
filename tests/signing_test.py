#!/usr/bin/env python3
"""Android only updates an app from the key it was installed with, so the key must
not depend on the folder or the machine (#6). Two builds from fresh folders, the way
the Termux command makes them, get the key PC builds sign with.

Needs keytool on PATH. Downloads uber-apk-signer unless it is already in
balatro-mobile-maker/."""
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
os.chdir(ROOT)
import build  # noqa: E402

# The certificate of every PC build since the reboot. Installed apps carry it:
# a new uber-apk-signer with another key inside must not get past this.
PC_KEY = "1E:08:A9:03:AE:F9:C3:A7:21:51:0B:64:EC:76:4D:01:D3:D0:94:EB:95:41:61:B6:25:44:EA:8F:18:7B:59:53"


def certificate(keystore):
    listing = subprocess.run(["keytool", "-list", "-v", "-keystore", keystore, "-storepass", "android"],
                             capture_output=True, text=True, check=True).stdout
    return re.search(r"SHA256: ([0-9A-F:]+)", listing).group(1)


def main():
    with tempfile.TemporaryDirectory() as tmp:
        jar = os.path.join(tmp, "uber-apk-signer.jar")
        cached = os.path.join(ROOT, "balatro-mobile-maker", "uber-apk-signer.jar")
        if os.path.exists(cached):
            shutil.copy(cached, jar)
        else:
            build._download(build.SIGNER_URL, jar)

        for fresh in ("first", "second"):
            build.WORKDIR = os.path.join(tmp, fresh)
            os.makedirs(build.WORKDIR)
            got = certificate(build._ensure_debug_keystore(jar))
            assert got == PC_KEY, f"{fresh} build signs with {got}"
            # A second build from the same folder keeps it.
            assert certificate(build._ensure_debug_keystore(jar)) == PC_KEY
    print("all passed")


if __name__ == "__main__":
    main()
