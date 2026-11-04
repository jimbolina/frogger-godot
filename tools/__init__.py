"""Shared roots of the tools tree; see docs/reference/testing/README.md."""
from pathlib import Path

TOOLS_ROOT = Path(__file__).resolve().parent
REPO_ROOT = TOOLS_ROOT.parent
