"""Shared fixtures. Every test here runs offline: no cluster, no network, no secrets."""
import importlib.util
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parent.parent


def load_module(name: str, rel_path: str):
    """Import a script by file path (several live in dirs whose names aren't valid package
    names, e.g. `open-incident.py`)."""
    path = REPO / rel_path
    sys.path.insert(0, str(path.parent))
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="session")
def repo() -> Path:
    return REPO


@pytest.fixture(scope="session")
def classify():
    return load_module("classify", "drills/lib/classify.py")


@pytest.fixture(scope="session")
def clocks():
    return load_module("clocks", "drills/lib/clocks.py")


@pytest.fixture(scope="session")
def emit():
    return load_module("emit", "drills/lib/emit.py")


@pytest.fixture
def valid_record():
    return {
        "drill_id": "ns-restore-20260101000000",
        "scenario": "ns-restore",
        "git_sha": "abc1234",
        "cluster_profile": "core",
        "controls": ["DORA-Art11"],
        "verdict": "pass",
        "integrity_check": "pass",
        "t_inject": "2026-01-01T00:00:00Z",
        "t_recover": "2026-01-01T00:02:00Z",
        "measured_rto_seconds": 120,
        "measured_rpo_records_lost": 0,
    }
