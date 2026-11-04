"""Shared input configuration. Run scripts through code/replicate.py."""
from pathlib import Path
import json, os
ROOT = Path(__file__).resolve().parents[2]
CONFIG = Path(os.environ.get("PROJECT_CONFIG", ROOT / "config/paths.example.json"))
VALUES = json.loads(CONFIG.read_text())
def path(key):
    value = Path(VALUES[key]).expanduser()
    return value if value.is_absolute() else ROOT / value
def output(key):
    value = path(key)
    value.parent.mkdir(parents=True, exist_ok=True)
    return value
