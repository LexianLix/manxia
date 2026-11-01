"""Compatibility entry point for the shared launcher asset generator."""
from pathlib import Path
import runpy

runpy.run_path(str(Path(__file__).with_name('generate-icons.py')), run_name='__main__')
