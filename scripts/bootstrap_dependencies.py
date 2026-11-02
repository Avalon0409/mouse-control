#!/usr/bin/env python3
"""Fetch the upstream revisions recorded in docs/upstreams.json without modifying existing checkouts."""
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    for item in json.loads((ROOT / "docs/upstreams.json").read_text())["repositories"]:
        target = ROOT / item["path"]
        if not target.exists():
            target.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(["git", "init", str(target)], check=True)
            subprocess.run(["git", "-C", str(target), "remote", "add", "origin", item["url"]], check=True)
            subprocess.run(["git", "-C", str(target), "fetch", "--depth", "1", "origin", item["commit"]], check=True)
            subprocess.run(["git", "-C", str(target), "checkout", "--detach", "FETCH_HEAD"], check=True)
        actual = subprocess.check_output(["git", "-C", str(target), "rev-parse", "HEAD"], text=True).strip()
        if actual != item["commit"]:
            raise RuntimeError(f"{item['name']} is at another revision; existing checkout was preserved")
    framework = ROOT / "references/Scroll-Reverser/Sparkle.framework/Sparkle"
    if not framework.exists():
        raise RuntimeError("The pinned Scroll Reverser checkout is missing Sparkle.framework")
    print("Pinned upstream dependencies verified")


if __name__ == "__main__":
    main()
