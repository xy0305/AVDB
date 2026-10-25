"""Compatibility entry point: preserved neutral regressions, never OnlineProbe256."""
import runpy
from pathlib import Path
runpy.run_path(str(Path(__file__).with_name('test-playback-diagnostics257.py')),run_name='__main__')
