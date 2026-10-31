"""Portable checks for the Xcode references, assets and shared screen inventory."""
import json
import re
from pathlib import Path
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parent.parent
project_dir = root / "HospitalUniversitario"
project = (project_dir / "HospitalUniversitario.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
definitions = re.findall(r"^\t\t([A-F0-9]{24})\s+(?:/\*.*?\*/\s*)?=\s*\{", project, re.M)
assert len(definitions) == len(set(definitions)), "Duplicate Xcode object IDs"
references = set(re.findall(r"\b[A-F0-9]{24}\b", project))
assert references.issubset(set(definitions)), "Dangling Xcode object references"
for resource in ["hospital-core.js", "contract.json", "screens.json"]:
    assert (project_dir / "HospitalUniversitario/Shared" / resource).is_file(), resource
    assert f"path = HospitalUniversitario/Shared/{resource}; sourceTree = SOURCE_ROOT" in project
    assert f"{resource} in Resources" in project
assert (project_dir / "HospitalUniversitario/Preview Content").is_dir()
assert 'SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";' in project
assert "SDKROOT = auto" not in project
ET.parse(project_dir / "HospitalUniversitario.xcodeproj/xcshareddata/xcschemes/HospitalUniversitario.xcscheme")
catalog = json.loads((project_dir / "HospitalUniversitario/Shared/screens.json").read_text(encoding="utf-8"))
inventory = json.loads((root / "docs/design-reference/inventory.json").read_text(encoding="utf-8"))
assert len(catalog["patient"]) == 11 and len(catalog["doctor"]) == 9
assert len(inventory) == 21  # Referencias históricas: se conserva la antigua pantalla del doctor.
assert sum(len(screens) for screens in catalog.values()) == 20
assert not any(screen["id"] == "appointments" for screen in catalog["doctor"])
assert any(screen["id"] == "appointments" for screen in catalog["patient"])
for role, screens in catalog.items():
    assert len({screen["id"] for screen in screens}) == len(screens), role
    assert screens[0]["id"] == "home"
for item in inventory:
    assert (root / "docs/design-reference" / item["file"]).is_file()
assert not any("../" in path for path in re.findall(r"path = ([^;]+);", project))
print("Xcode: referencias, recursos explícitos, esquema, 20 pantallas activas y 21 referencias históricas verificados.")
print("Esta comprobación no compila Swift ni sustituye xcodebuild en una Mac.")
