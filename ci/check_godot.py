"""Godot can return exit 0 after script errors; inspect output as well."""
import subprocess
import sys

commands = [
    ['--headless', '--editor', '--import', '--path', '.', '--quit'],
    ['--headless', '--path', '.', '--script', 'tests/test_game_services.gd'],
]
for args in commands:
    result = subprocess.run([sys.argv[1], *args], capture_output=True, text=True, timeout=120)
    output = result.stdout + result.stderr
    if result.returncode or 'SCRIPT ERROR' in output or 'Parse Error' in output or 'ERROR:' in output:
        print(output)
        raise SystemExit(result.returncode or 1)
    print('Passed:', ' '.join(args))
