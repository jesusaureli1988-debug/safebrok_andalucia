"""Verify the SDK manifest in the final IPA before publishing to Apple."""
import plistlib
import sys
import zipfile
from pathlib import Path


def check_ipa(path):
    with zipfile.ZipFile(path) as ipa:
        manifests = [name for name in ipa.namelist()
                     if name.startswith("Payload/")
                     and "package_info_plus" in name
                     and name.endswith("/PrivacyInfo.xcprivacy")]
        if not manifests:
            raise ValueError("El IPA no incluye el manifiesto de package_info_plus")
        for name in manifests:
            manifest = plistlib.loads(ipa.read(name))
            if not isinstance(manifest, dict) or "NSPrivacyTracking" not in manifest:
                raise ValueError(f"Manifiesto de privacidad no valido: {name}")
            print(f"OK SDK privacy manifest: {name}")


if __name__ == "__main__":
    paths = [Path(arg) for arg in sys.argv[1:]] or list(Path("build/ios/ipa").glob("*.ipa"))
    if not paths:
        raise SystemExit("No se ha generado ningun IPA para validar")
    for path in paths:
        check_ipa(path)
