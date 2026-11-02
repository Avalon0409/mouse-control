#!/usr/bin/env python3
"""Build with a persistent, project-only development identity outside the repository."""
import argparse
from datetime import datetime
import hashlib
import os
from pathlib import Path
import secrets
import shlex
import subprocess
import tempfile
import plistlib

ROOT = Path(__file__).resolve().parents[1]
SIGNING = Path.home() / "Library/Application Support/MouseControl/DevelopmentSigning"


def run(arguments, **kwargs):
    # Do not echo commands: keychain commands carry generated local passwords.
    result = subprocess.run(arguments, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)
    if result.returncode:
        raise RuntimeError(f"{Path(arguments[0]).name} failed (exit {result.returncode})")
    return result.stdout


def identity():
    if SIGNING.exists() and not (SIGNING / "ready").exists():
        # Preserve failed setup rather than replacing any previously usable signing key.
        SIGNING.rename(SIGNING.with_name("DevelopmentSigning-incomplete-" + datetime.now().strftime("%Y%m%d-%H%M%S")))
    SIGNING.mkdir(parents=True, exist_ok=True, mode=0o700)
    SIGNING.chmod(0o700)
    password_file = SIGNING / "keychain-password"
    keychain = SIGNING / "development.keychain-db"
    certificate = SIGNING / "certificate.pem"
    if not keychain.exists():
        password_file.write_text(secrets.token_urlsafe(48))
        password_file.chmod(0o600)
        password = password_file.read_text()
        search_list = shlex.split(run(["security", "list-keychains", "-d", "user"]).decode())
        run(["security", "create-keychain", "-p", password, str(keychain)])
        run(["security", "list-keychains", "-d", "user", "-s", *search_list])
        with tempfile.TemporaryDirectory(prefix="mousecontrol-signing-", dir=SIGNING) as temporary:
            private_key = Path(temporary) / "private-key.pem"
            archive = Path(temporary) / "identity.p12"
            run(["openssl", "req", "-new", "-newkey", "rsa:3072", "-x509", "-sha256", "-days", "3650",
                 "-keyout", str(private_key), "-out", str(certificate), "-passout", f"file:{password_file}",
                 "-subj", "/CN=MouseControl Local Development/",
                 "-addext", "basicConstraints=critical,CA:FALSE",
                 "-addext", "keyUsage=critical,digitalSignature",
                 "-addext", "extendedKeyUsage=critical,codeSigning"])
            certificate.chmod(0o600)
            # Apple's PKCS#12 importer supports this wrapping on older supported macOS releases.
            run(["openssl", "pkcs12", "-export", "-in", str(certificate), "-inkey", str(private_key),
                 "-out", str(archive), "-passin", f"file:{password_file}", "-passout", "env:MOUSECONTROL_SIGNING_PASSWORD",
                 "-certpbe", "PBE-SHA1-3DES", "-keypbe", "PBE-SHA1-3DES", "-macalg", "sha1"],
                env={**os.environ, "MOUSECONTROL_SIGNING_PASSWORD": password})
            run(["security", "import", str(archive), "-k", str(keychain), "-P", password,
                 "-T", "/usr/bin/codesign"])
        (SIGNING / "ready").write_text("Local development identity\n")
    if not password_file.exists() or not certificate.exists():
        raise RuntimeError("Development signing setup is incomplete; preserve the signing folder for repair")
    password = password_file.read_text()
    run(["security", "unlock-keychain", "-p", password, str(keychain)])
    run(["security", "set-key-partition-list", "-S", "apple-tool:,apple:", "-s", "-k", password, str(keychain)])
    der = run(["openssl", "x509", "-in", str(certificate), "-outform", "DER"])
    return hashlib.sha1(der).hexdigest(), keychain


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--configuration", choices=["Debug", "Local", "Release"], default="Local")
    parser.add_argument("--derived-data", type=Path, default=ROOT / "build/LocalDerivedData")
    arguments = parser.parse_args()
    os.umask(0o077)
    commit = run(["git", "rev-parse", "HEAD"], cwd=ROOT).decode().strip()
    tag = ""
    version = None
    if arguments.configuration == "Release":
        if run(["git", "status", "--porcelain", "--untracked-files=no"], cwd=ROOT).strip():
            raise RuntimeError("Release builds require a clean committed working tree")
        tag = run(["git", "describe", "--tags", "--exact-match", "HEAD"], cwd=ROOT).decode().strip()
        import re
        if not re.fullmatch(r"v\d+\.\d+\.\d+", tag):
            raise RuntimeError("Release builds require a stable vMAJOR.MINOR.PATCH tag")
        version = tag[1:]
    fingerprint, keychain = identity()
    command = ["xcodebuild", "-project", str(ROOT / "app/MouseControl.xcodeproj"), "-scheme", "MouseControl",
               "-configuration", arguments.configuration, "-derivedDataPath", str(arguments.derived_data.resolve()),
               "CODE_SIGNING_ALLOWED=NO", "ENABLE_HARDENED_RUNTIME=NO"]
    if version:
        build_number = run(["git", "rev-list", "--count", "HEAD"], cwd=ROOT).decode().strip()
        command += [f"MARKETING_VERSION={version}", f"CURRENT_PROJECT_VERSION={build_number}", "ARCHS=arm64 x86_64", "ONLY_ACTIVE_ARCH=NO"]
    command.append("build")
    result = subprocess.run(command, cwd=ROOT)
    if result.returncode:
        raise SystemExit(result.returncode)
    bundle = arguments.derived_data.resolve() / f"Build/Products/{arguments.configuration}/MouseControl.app"
    info_path = bundle / "Contents/Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    info["MouseControlGitCommit"] = commit
    info["MouseControlGitTag"] = tag
    info["OpenSnekBuildChannel"] = "release" if version else "dev"
    info_path.write_bytes(plistlib.dumps(info))
    # Xcode only searches system keychains. Sign afterward so the development keychain
    # stays outside the system search list and no trust settings need to change.
    nested = [path for path in bundle.rglob("*") if not path.is_symlink() and path.suffix in {".dylib", ".framework", ".xpc", ".app"}]
    for path in [*sorted(nested, key=lambda path: len(path.parts), reverse=True), bundle]:
        run(["codesign", "--force", "--sign", fingerprint, "--keychain", str(keychain), "--timestamp=none",
             "--preserve-metadata=entitlements,flags", str(path)])
    run(["codesign", "--verify", "--deep", "--strict", str(bundle)])
    print(f"Verified local build: {bundle}")


if __name__ == "__main__":
    main()
