#!/usr/bin/env python3
"""Check that the tools tree imports itself by package path.

Every `from tools...` and `import tools...` statement under tools/ must name an
existing module, every module so imported must import cleanly, every script
must compile, and every script must find the repository through the one
bootstrap line and `tools.REPO_ROOT` rather than its own folder.

Stdlib only, asset-free: `python3 tools/check/test_tool_imports.py`.
"""
import ast
import importlib
import os
import py_compile
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools import REPO_ROOT, TOOLS_ROOT

BOOTSTRAP = 'sys.path.insert(0, str(Path(__file__).resolve().parents[2]))'
ROOT_ATTRIBUTES = {'REPO_ROOT', 'TOOLS_ROOT'}
FORBIDDEN = ('parent.parent', 'dirname(dirname(', 'sys.path.insert(0, os.path.dirname(')
BARE_PREFIXES = ('import make_golden_', 'import org1_', 'import verify_', 'import compare_', 'import run_',
                 'import godot_', 'import angular_glyphs', 'import imported_assets_common')


def scripts():
    """Every Python source under tools/, sorted, skipping bytecode caches."""
    return sorted(path for path in TOOLS_ROOT.rglob('*.py') if '__pycache__' not in path.parts)


def module_file(name):
    """The source file of the dotted module name under the repository, or None."""
    base = REPO_ROOT.joinpath(*name.split('.'))
    for candidate in (base.with_suffix('.py'), base / '__init__.py'):
        if candidate.is_file():
            return candidate
    return None


def tools_imports(path):
    """(line, module, problem) for each tools import in path; problem is '' when the target exists."""
    found = []
    for node in ast.walk(ast.parse(path.read_text(encoding='utf-8'), str(path))):
        if isinstance(node, ast.ImportFrom) and node.level == 0 and node.module and \
                (node.module == 'tools' or node.module.startswith('tools.')):
            if module_file(node.module) is None:
                found.append((node.lineno, node.module, 'no module ' + node.module))
                continue
            package = module_file(node.module).name == '__init__.py'
            for alias in node.names:
                if node.module == 'tools' and alias.name in ROOT_ATTRIBUTES:
                    continue
                if package:
                    target = node.module + '.' + alias.name
                    found.append((node.lineno, target, '' if module_file(target) else 'no module ' + target))
                else:
                    found.append((node.lineno, node.module, ''))
        elif isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == 'tools' or alias.name.startswith('tools.'):
                    found.append((node.lineno, alias.name, '' if module_file(alias.name) else 'no module ' + alias.name))
    return found


class ToolImportTests(unittest.TestCase):
    def test_tools_imports_name_existing_modules(self):
        missing = ['%s:%d: %s' % (path.relative_to(REPO_ROOT), line, problem)
                   for path in scripts() for line, _, problem in tools_imports(path) if problem]
        self.assertEqual(missing, [], '\n'.join(missing))

    def test_imported_modules_load(self):
        targets = sorted({module for path in scripts() for _, module, problem in tools_imports(path) if not problem})
        if str(REPO_ROOT) not in sys.path:
            sys.path.insert(0, str(REPO_ROOT))
        failures = []
        for module in targets:
            try:
                importlib.import_module(module)
            except BaseException as error:
                failures.append('%s: %s: %s' % (module, type(error).__name__, error))
        self.assertEqual(failures, [], '\n'.join(failures))

    def test_scripts_compile(self):
        failures = []
        with tempfile.TemporaryDirectory() as folder:
            for index, path in enumerate(scripts()):
                try:
                    py_compile.compile(str(path), cfile=os.path.join(folder, '%d.pyc' % index), doraise=True)
                except py_compile.PyCompileError as error:
                    failures.append(str(error))
        self.assertEqual(failures, [], '\n'.join(failures))

    def test_repository_root_convention(self):
        exempt = {TOOLS_ROOT / '__init__.py', Path(__file__).resolve()}
        failures = []
        for path in scripts():
            if path in exempt:
                continue
            for number, line in enumerate(path.read_text(encoding='utf-8').splitlines(), 1):
                where = '%s:%d: %s' % (path.relative_to(REPO_ROOT), number, line.strip())
                if '.parents[' in line and line.strip() != BOOTSTRAP:
                    failures.append(where)
                elif any(pattern in line for pattern in FORBIDDEN):
                    failures.append(where)
                elif line.startswith(BARE_PREFIXES):
                    failures.append(where)
        self.assertEqual(failures, [], '\n'.join(failures))


if __name__ == '__main__':
    unittest.main()
