#!/usr/bin/env python3
"""Package an already signed, tagged Release build and generate its signed Sparkle feed."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
UPDATE_KEY = Path.home() / "Library/Application Support/MouseControl/UpdateSigning/private.pem"
SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    bundle = args.app.resolve()
    info = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
    version, tag, commit = info["CFBundleShortVersionString"], info["MouseControlGitTag"], info["MouseControlGitCommit"]
    if tag != "v" + version or info["OpenSnekBuildChannel"] != "release":
        raise RuntimeError("Application metadata does not describe a tagged Release build")
    if subprocess.check_output(["git", "rev-parse", tag + "^{commit}"], cwd=ROOT, text=True).strip() != commit:
        raise RuntimeError("The application commit differs from its Git tag")
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(bundle)], check=True)
    architectures = subprocess.check_output(["lipo", "-archs", str(bundle / "Contents/MacOS/MouseControl")], text=True).strip().split()
    if set(architectures) != {"arm64", "x86_64"}:
        raise RuntimeError("Release application must contain both Apple Silicon and Intel architectures")
    args.output.mkdir(parents=True, exist_ok=True)
    archive = args.output / f"MouseControl-{version}.zip"
    if archive.exists():
        raise RuntimeError("Release archive already exists; preserve it or choose another output directory")
    subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(bundle), str(archive)], check=True)
    public = subprocess.check_output(["openssl", "pkey", "-in", str(UPDATE_KEY), "-pubout", "-outform", "DER"])[-32:]
    if base64.b64encode(public).decode() != info["SUPublicEDKey"]:
        raise RuntimeError("Update signing key differs from the application's public key")
    with tempfile.TemporaryDirectory(dir=args.output) as temporary:
        signature = Path(temporary) / "signature"
        subprocess.run(["openssl", "pkeyutl", "-sign", "-rawin", "-inkey", str(UPDATE_KEY), "-in", str(archive), "-out", str(signature)], check=True)
        public_file = Path(temporary) / "public.pem"
        subprocess.run(["openssl", "pkey", "-in", str(UPDATE_KEY), "-pubout", "-out", str(public_file)], check=True, capture_output=True)
        subprocess.run(["openssl", "pkeyutl", "-verify", "-rawin", "-pubin", "-inkey", str(public_file), "-in", str(archive), "-sigfile", str(signature)], check=True, capture_output=True)
        ed_signature = base64.b64encode(signature.read_bytes()).decode()
    base = f"https://github.com/Avalon0409/mouse-control/releases/download/{tag}"
    ET.register_namespace("sparkle", SPARKLE)
    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "MouseControl updates"
    item = ET.SubElement(channel, "item")
    ET.SubElement(item, "title").text = "MouseControl " + version
    ET.SubElement(item, f"{{{SPARKLE}}}minimumSystemVersion").text = "14.0"
    ET.SubElement(item, "enclosure", {"url": f"{base}/{archive.name}", "length": str(archive.stat().st_size), "type": "application/octet-stream",
                                     f"{{{SPARKLE}}}version": str(info["CFBundleVersion"]), f"{{{SPARKLE}}}shortVersionString": version,
                                     f"{{{SPARKLE}}}edSignature": ed_signature})
    ET.ElementTree(rss).write(args.output / "appcast.xml", encoding="utf-8", xml_declaration=True)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    (args.output / "SHA256SUMS.txt").write_text(f"{digest}  {archive.name}\n")
    (args.output / "release-manifest.json").write_text(json.dumps({"version": version, "tag": tag, "commit": commit, "build": info["CFBundleVersion"],
                                                                "archive": archive.name, "sha256": digest, "architectures": sorted(architectures),
                                                                "minimumMacOS": "14.0", "signing": "Local development certificate; not notarized"}, indent=2) + "\n")
    print(f"Packaged {tag} at {commit[:12]}: {archive}")


if __name__ == "__main__":
    main()
