"""Dry checks of specs/characters.lua: its tests' verdicts, the legacy scenarios they came from, and the checks of their own lines."""
NAMES = {}  # each legacy scenario moved here, by its old name: [the names of its tests in this spec]
WANT = {}  # each test's verdict under `tags all` when nothing fails, by "characters > <test>"
TESTS = []
