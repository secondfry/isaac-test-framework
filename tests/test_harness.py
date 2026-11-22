"""Dry run of main.lua against the stub in tests/stub/. Run: python -B -I tests/test_harness.py main.lua [test ...] (venv with lupa); no test names runs
them all, module by module. Each tests/test_<name>.py module is found by itself (dry.modules) and exports TESTS (its test functions) and WANT
(its tests' verdicts)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # -I leaves the script's folder off sys.path
import dry  # noqa: E402


def main(path, names):
    by_name = {}
    for m in dry.modules():
        for t in m.TESTS:
            assert t.__name__ not in by_name, f"two tests named {t.__name__}"
            by_name[t.__name__] = t
    for name in names or by_name:
        by_name[name](path)
    print("PASS dry run")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2:])
