"""Package a committed company release without local data or credential files."""
import argparse
import hashlib
import io
import json
import re
import subprocess
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def git(*args, cwd=ROOT):
    return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True).stdout


def submodules(repository=ROOT, prefix=""):
    result = []
    for record in git("ls-tree", "-r", "-z", "HEAD", cwd=repository).split(b"\0"):
        if not record:
            continue
        metadata, raw_path = record.split(b"\t", 1)
        mode, _, revision = metadata.decode().split()
        if mode != "160000":
            continue
        path = raw_path.decode("utf-8")
        checkout = (repository / path).resolve()
        if not checkout.is_relative_to(ROOT):
            raise RuntimeError("Submodule checkout is outside the repository")
        actual = git("rev-parse", "HEAD", cwd=checkout).decode().strip()
        if actual != revision:
            raise RuntimeError(f"Initialize the pinned submodule before packaging: {prefix}{path}")
        result.append((prefix + path, revision, checkout))
        result.extend(submodules(checkout, prefix + path + "/"))
    return result


def add_archive(destination, payload):
    existing = set(destination.namelist())
    with zipfile.ZipFile(io.BytesIO(payload)) as source:
        for entry in source.infolist():
            if entry.filename not in existing:
                destination.writestr(entry, source.read(entry.filename))
                existing.add(entry.filename)


def package(tag, output):
    declared = (ROOT / "COMPANY_RELEASE").read_text(encoding="utf-8").strip()
    if not re.fullmatch(r"v\d+\.\d+\.\d+-company\.\d+", tag) or tag != declared:
        raise RuntimeError("Release tag must match COMPANY_RELEASE and use vX.Y.Z-company.N")
    if git("status", "--porcelain", "--untracked-files=no").strip():
        raise RuntimeError("Commit tracked changes and keep submodules clean before packaging")
    revision = git("rev-parse", "HEAD").decode().strip()
    commit_time = git("show", "-s", "--format=%cI", "HEAD").decode().strip()
    modules = submodules()
    output.mkdir(parents=True, exist_ok=True)
    manifest = {"release": tag, "commit": revision, "commit_time": commit_time,
                "upstream_client_version": "1.5.1", "management_api_version": "0.1.0",
                "database_schema": 2, "prerelease": True,
                "submodules": {path: sha for path, sha, _ in modules},
                "verification": "See management/VALIDATION.md; packaging is not a native client build"}
    manifest_bytes = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode()
    source_path = output / f"rustdesk-source-{tag}.zip"
    prefix = f"rustdesk-source-{tag}/"
    source_path.write_bytes(git("archive", "--format=zip", f"--prefix={prefix}", "HEAD"))
    with zipfile.ZipFile(source_path, "a", compression=zipfile.ZIP_DEFLATED) as archive:
        for path, _, checkout in modules:
            add_archive(archive, git("archive", "--format=zip", f"--prefix={prefix}{path}/", "HEAD", cwd=checkout))
        archive.writestr(prefix + "release-manifest.json", manifest_bytes)
    tracked = [p.decode("utf-8") for p in git("ls-files", "-z").split(b"\0") if p]
    management_path = output / f"rustdesk-management-{tag}.zip"
    bundle_prefix = f"rustdesk-management-{tag}/"
    extra = {"LICENCE", "docs/company-management-design.md", f"docs/releases/{tag}.md"}
    with zipfile.ZipFile(management_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in tracked:
            if path.startswith("management/") or path in extra:
                archive.writestr(bundle_prefix + path, git("show", f"HEAD:{path}"))
        archive.writestr(bundle_prefix + "release-manifest.json", manifest_bytes)
        archive.writestr(bundle_prefix + "README.md", (
            f"# RustDesk management {tag}\n\n"
            "Enter management/ and follow README.md to deploy the self-hosted service.\n"
            "No administrator account, database, device credential or native client binary is bundled.\n"
            "See docs/releases/ for release notes and management/VALIDATION.md for tested scope.\n"))
    manifest_path = output / "release-manifest.json"
    manifest_path.write_bytes(manifest_bytes)
    notes = output / f"release-notes-{tag}.md"
    notes.write_bytes(git("show", f"HEAD:docs/releases/{tag}.md"))
    files = [management_path, source_path, manifest_path, notes]
    (output / "SHA256SUMS").write_text("".join(
        f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n" for path in files), encoding="utf-8")
    for path in files + [output / "SHA256SUMS"]:
        print(f"{path.name}: {path.stat().st_size} bytes")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--output", type=Path, default=ROOT / "dist/company-release")
    args = parser.parse_args()
    package(args.tag, args.output.resolve())
