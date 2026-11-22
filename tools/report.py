"""Verdict on a harness session: python -B -I tools/report.py <log.txt> [--out DIR] [--specs DIR] [--timeline TEST]. Exit 0 only on ALL PASS.

Reads log.txt (or a dry run's PROBE lines) and prints each test's RESULT with its INFO answers, every ASSERT FAIL with the lines before
it, snapshot differences, the continues, errors outside known noise and log guard hits, then one verdict line: ALL PASS or
NEEDS ANALYSIS: <reasons>. Writes and compares specs/<spec>.snap.txt, writes <out>/traces/<spec> - <test>.txt for each failed, new or
changed test, and <out>/report.json. --timeline TEST prints that test's TRACE lines as a timeline, characters labelled by GetPtrHash.
"""
import argparse
import datetime
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
# Lines the error pattern matches that runs 6-8 showed to be benign, each with why.
NOISE = [
    "Different number of collectibles",  # engine [WARN] at every game start, harness or not (runs 6-8: 10-25 per run)
    "Could not find provider",  # Stats+ (WARN) at load: its essentials addon has no provider for three options; unrelated to ReHUD
]
# Case-sensitive, so the engine's lowercase "[warn] AnmCache" INFO lines (run 7, sprite cache on exit) stay out.
ERROR = re.compile(r'\[(WARN|ERROR)\]|\((WARN|ERROR)\)|\]ERROR:|Error in "|Lua stack trace|Caught exception|attempt to ')
# Unreached steps chance alone explains: the test could not reach a path this session. Any other needs a look.
EXPLAINED = [
    "no split in 20 Clicker uses",  # Clicker rolls a random character and may never land on Jacob & Esau
    "Zodiac rolled the same item",  # the stage re-roll can repeat
    "3 Dollar Bill still grants",  # the next grant can roll the same item
]
PROBE = re.compile(r"(?:^|Lua Debug: )PROBE (.*)")
ENGINE = "[INFO] - Binding of Isaac: Repentance+ v"  # the engine's own line: absent from dry logs, so they never write snapshots
START = re.compile(r"HARNESS START (\d+) tests, tags '(.*?)', update snapshots (yes|no)")
RESULT = re.compile(r"RESULT (.+?) > (.+?) (PASS|FAIL|RECORDED|SKIP)\b ?(.*)")
TRACE_U = re.compile(r"TRACE u(\d+) ")
ASK = "ACTION exit to the menu and Continue now by type"
RESUMED = "DONE exit to the menu and Continue now"
LATE = "; late Continue mid-test"
UNREACHED = "; unreached: "
SNAP_HEADER = "# {spec} snapshots, written by tools/report.py from a played session"


def guard_hit(raw):
    """A mod update or Lua reset mid-session (isaac-lan tools/testing/engine.py:18-24); a mod's Lua Debug line never starts so."""
    return raw.startswith("[INFO] - Updating mod '") or raw.strip() == "[INFO] - Lua is resetting!"


def fold_digits(text):
    return re.sub(r"\d+", "N", text)


class Test:
    def __init__(self, spec, name):
        self.spec, self.name = spec, name
        self.status, self.verdict, self.assertions, self.late = None, "", None, False
        self.failures, self.unreached, self.teardown = [], [], []
        self.snaps, self.lines, self.out = {}, [], []
        self.updates, self.snapshot, self.trace = None, None, None

    @property
    def key(self):
        return f"{self.spec} > {self.name}"

    def failed(self):
        return bool(self.failures)


class Session:
    def __init__(self):
        self.total, self.tags, self.update, self.version, self.start = None, None, False, None, None
        self.done, self.guard, self.harness_errors, self.started = False, [], [], []
        self.tests, self.errors, self.out = {}, {}, []
        self.asks = self.resumed = 0


class Reader:
    """One pass over the log: each PROBE line goes to the handler of its prefix, every other line to the guard and error scan."""

    def __init__(self):
        self.s, self.open, self.seg, self.recent = Session(), None, [], []

    def feed(self, raw):
        raw = raw.rstrip("\r\n")
        if raw.startswith(ENGINE):
            self.s.version = raw[len("[INFO] - "):]
        if guard_hit(raw):
            self.s.guard.append(raw.strip())
        was = self.open
        if was:
            was.lines.append(raw)
        m = PROBE.search(raw)
        if not m:
            self.scan_error(raw)
            return
        text = m.group(1)
        handler = next((h for prefix, h in HANDLERS if text.startswith(prefix)), None)
        if handler:
            handler(self, text)
        if self.open and self.open is not was:  # its TEST START line opens the trace
            self.open.lines.append(raw)
        self.recent = (self.recent + [text])[-4:]

    def scan_error(self, raw):
        if not ERROR.search(raw) or any(n in raw for n in NOISE):
            return
        first, n = self.s.errors.get(fold_digits(raw), (raw, 0))
        self.s.errors[fold_digits(raw)] = (first, n + 1)

    def test(self, spec, name):
        return self.s.tests.setdefault(f"{spec} > {name}", Test(spec, name))

    def harness_start(self, text):
        self.s.out.append(text)
        m = START.match(text)
        if m:
            self.s.total, self.s.tags, self.s.update = int(m.group(1)), m.group(2), m.group(3) == "yes"

    def harness_done(self, text):
        self.s.done = True

    def harness_error(self, text):
        self.s.harness_errors.append(text)

    def test_start(self, text):
        spec, _, name = text[len("TEST START "):].partition(" > ")
        self.open = self.test(spec, name)
        self.s.started.append(self.open.key)

    def result(self, text):
        t = self.result_test(text)
        if t is None:
            return
        parse_result(t, text[len("RESULT " + t.key + " "):])
        if self.s.guard:
            t.failures.append("environment changed: " + self.s.guard[0])
        t.out = fold_infos(t, self.seg)
        self.seg, self.open = [], None

    def result_test(self, text):
        """The open test when the line names it (a FAIL why may hold a verdict word), else the names the line gives (a SKIP)."""
        if self.open and text.startswith("RESULT " + self.open.key + " "):
            return self.open
        m = RESULT.match(text)
        return self.test(m.group(1), m.group(2)) if m else None

    def assert_fail(self, text):
        self.seg.append("  " + text)
        self.seg.extend("      | " + c for c in self.recent[-4:])
        if self.open:
            self.open.failures.append(text)

    def snap(self, text):
        prefix = f"SNAP {self.open.key} | " if self.open else None
        if not prefix or not text.startswith(prefix):
            return
        key, _, value = text[len(prefix):].partition(" = ")
        self.open.snaps[key] = value

    def teardown_fail(self, text):
        t = self.open or next(reversed(self.s.tests.values()), None)  # teardown runs as its test ends, around the RESULT
        if t:
            t.teardown.append(text)

    def info(self, text):
        self.seg.append(text)

    def ask(self, text):
        self.s.asks += 1
        self.seg.append("  continue: asked")

    def game_start(self, text):
        if text.endswith("continued true"):
            self.seg.append("  continue: game continued")

    def resumed(self, text):
        self.s.resumed += 1
        self.seg.append("  continue: resumed " + text.split("Continue now ", 1)[1])

    def trace(self, text):
        m = TRACE_U.match(text)
        if m and self.open:
            self.open.updates = max(self.open.updates or 0, int(m.group(1)))

    def finish(self):
        self.s.out.extend(self.seg)  # lines after the last RESULT: a test cut off
        return self.s


HANDLERS = [
    ("HARNESS START", Reader.harness_start), ("HARNESS DONE", Reader.harness_done), ("HARNESS ERROR", Reader.harness_error),
    ("TEST START ", Reader.test_start), ("RESULT ", Reader.result), ("ASSERT FAIL", Reader.assert_fail), ("SNAP ", Reader.snap),
    ("TEARDOWN FAIL", Reader.teardown_fail), ("INFO ", Reader.info), (ASK, Reader.ask), ("GAME START", Reader.game_start),
    (RESUMED, Reader.resumed), ("TRACE u", Reader.trace),
]


def parse_result(t, rest):
    """Status, assertion count, FAIL why, unreached steps and the late Continue note of one RESULT line's tail."""
    t.verdict, t.late = rest, rest.endswith(LATE)
    rest = rest[:-len(LATE)] if t.late else rest
    rest, _, unreached = rest.partition(UNREACHED)
    t.unreached = unreached.split(", ") if unreached else []
    t.status, _, body = rest.partition(" ")
    if t.status == "PASS":
        t.assertions = int(body.split()[0]) if body[:1].isdigit() else None
    if t.status == "FAIL":
        t.failures.insert(0, body)


def fold_infos(t, seg):
    """The test's report lines: its RESULT, the non-INFO lines, then one row per INFO answer (a step number folds)."""
    out, infos = [f"{t.key}: {t.verdict}"], {}
    for line in seg:
        if not line.startswith("INFO "):
            out.append(line)
            continue
        text = next((line[len(p):] for p in (f"INFO {t.key} ", f"INFO {t.name} ") if line.startswith(p)), line[5:])
        head, sep, tail = text.partition(": ")
        key = fold_digits(head) + sep + tail if sep else text
        first, n = infos.get(key, (text, 0))
        infos[key] = (first, n + 1)
    return out + [f"  info {text}" + (f" (x{n})" if n > 1 else "") for text, n in infos.values()]


# Snapshots: specs/<spec>.snap.txt, one "## <test>" section each, its "# game ..., session ..." line, then key = value lines.

def read_snapshots(path):
    """{test: (meta line, {key: value})} in file order; {} when the file is absent."""
    if not os.path.exists(path):
        return {}
    sections, current = {}, None
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\r\n")
            if line.startswith("## "):
                current = sections.setdefault(line[3:], ["", {}])
            elif current is not None and line.startswith("# ") and not current[0]:
                current[0] = line
            elif current is not None and " = " in line:
                key, _, value = line.partition(" = ")
                current[1][key] = value
    return {name: (meta, values) for name, (meta, values) in sections.items()}


def write_snapshots(path, spec, sections):
    lines = [SNAP_HEADER.format(spec=spec), ""]
    for name, (meta, values) in sections.items():
        lines += [f"## {name}", meta] + [f"{k} = {v}" for k, v in values.items()] + [""]
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))


def differences(old, new):
    """Key by key, both values; a key only one side has shows None on the other."""
    return [{"key": k, "snapshot": old.get(k), "session": new.get(k)} for k in dict.fromkeys([*old, *new]) if old.get(k) != new.get(k)]


def snapshot_state(old, diff, update, writable):
    if old is None:
        return "new"
    if not diff:
        return "match"
    return "updated" if update and writable else "diff"


def apply_snapshots(s, specs_dir):
    """Compares every test with SNAP lines against its spec's file; writes new and updated sections of passing tests of a real session."""
    for spec in dict.fromkeys(t.spec for t in s.tests.values() if t.snaps):
        path = os.path.join(specs_dir, spec + ".snap.txt")
        sections, changed = read_snapshots(path), False
        for t in (t for t in s.tests.values() if t.spec == spec and t.snaps):
            changed |= apply_snapshot(t, sections, s)
        if changed:
            write_snapshots(path, spec, sections)


def apply_snapshot(t, sections, s):
    writable = bool(s.version) and not t.failed()
    old = sections[t.name][1] if t.name in sections else None
    diff = differences(old, t.snaps) if old is not None else []
    state = snapshot_state(old, diff, s.update, writable)
    write = writable and state in ("new", "updated")
    t.snapshot = {"state": state, "diff": diff, "written": write}
    if state == "diff":
        t.failures.append(f"snapshot differs in {len(diff)} keys")
    if write:
        sections[t.name] = (f"# game {s.version}, session {s.start}", dict(t.snaps))
    return write


def snapshot_lines(t):
    snap = t.snapshot
    if not snap:
        return []
    head = f"  snapshot {snap['state']}" + (", written" if snap["written"] else ", not written" if snap["state"] == "new" else "")
    return [head] + [f"    {d['key']}: snapshot {d['snapshot']!r}, session {d['session']!r}" for d in snap["diff"]]


# Traces and the verdict.

def write_traces(s, out_dir):
    for t in s.tests.values():
        if not t.lines or not (t.failed() or (t.snapshot and t.snapshot["state"] != "match")):
            continue
        t.trace = os.path.join(out_dir, "traces", f"{t.spec} - {t.name}.txt")
        os.makedirs(os.path.dirname(t.trace), exist_ok=True)
        with open(t.trace, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(t.lines) + "\n")


def test_reasons(t):
    odd = [u for u in t.unreached if not any(u.startswith(e) for e in EXPLAINED)]
    return ([f"{t.key} FAIL"] if t.failed() else []) + ([f"{t.key} unreached: {', '.join(odd)}"] if odd else []) \
        + ([f"{t.key} late Continue mid-test"] if t.late else []) + ([f"{t.key} teardown failed"] if t.teardown else [])


def session_reasons(s):
    results = [t for t in s.tests.values() if t.status]
    reasons = list(s.harness_errors) + [r for t in s.tests.values() for r in test_reasons(t)]
    if s.errors:
        reasons.append(f"{len(s.errors)} distinct errors")
    if s.guard:
        reasons.append("environment changed: " + s.guard[0])
    if s.total is None:
        reasons.append("no HARNESS START")
    elif len(results) != s.total:
        reasons.append(f"results for {len(results)} of {s.total} tests")
    if not s.done:
        reasons.append("no HARNESS DONE")
    lost = [k for k in s.started if not s.tests[k].status]
    if lost:
        reasons.append("started without a result: " + ", ".join(lost))
    if s.asks != s.resumed:
        reasons.append(f"continue asked {s.asks} times, resumed {s.resumed}")
    return reasons


def report_lines(s, reasons):
    out = s.out[:1]
    for t in s.tests.values():
        overruled = [f"  FAIL: {'; '.join(t.failures)}"] if t.failed() and t.status != "FAIL" else []  # a snapshot diff or the guard
        out += t.out + overruled + snapshot_lines(t) + [f"  {x}" for x in t.teardown] + ([f"  trace {t.trace}"] if t.trace else [])
    out += s.out[1:]
    if s.guard:
        out += ["log guard:"] + [f"  {g}" for g in s.guard]
    if s.errors:
        out += ["errors outside the noise list:"] + [f"  {raw}" + (f" (x{n})" if n > 1 else "") for raw, n in s.errors.values()]
    return out + ["ALL PASS" if not reasons else "NEEDS ANALYSIS: " + "; ".join(reasons)]


def report_json(s, reasons):
    tests = [{"spec": t.spec, "name": t.name, "tags": None, "status": "FAIL" if t.failed() else t.status, "assertions": t.assertions,
              "failures": t.failures, "unreached": t.unreached, "snapshot": t.snapshot, "teardown": t.teardown, "trace": t.trace,
              "updates": t.updates} for t in s.tests.values()]
    session = {"version": s.version, "tags": s.tags, "update": s.update, "guard": s.guard, "start": s.start, "done": s.done}
    return {"session": session, "tests": tests, "verdict": "ALL PASS" if not reasons else "NEEDS ANALYSIS", "reasons": reasons}


# The timeline of one test's TRACE lines, characters labelled by GetPtrHash (labels by seed merged Esau Jr. forms and twins, bug 7).

TRACE = re.compile(r"TRACE u(\d+) after (.*?): (PLAYER|PLAYERX|ROSTER|ENTRY|COUNT) (.*)")
TRACE_STEP = re.compile(r"TRACE u(\d+) step (.*) begins$")
PLAYER = re.compile(r"(\d+) type (\S+) seed (\S+) hash (\S+) ctrl \S+ parent (\S+) (.*) primary (\S+) secondary (\S+) pocket (\S+)$")
ROSTER = re.compile(r"key (\S+) number (\S+) swapped (\S+) partner (\S+) left (\S+)(?: type (\S+) group (\S+))?$")
ENTRY = re.compile(r"\d+ c(\d+) owner (\S+) floor (.*?)(?: merged (\S+) temporary (\S+))?$")


def labeller(prefix=""):
    """First-seen labels A, B, ... (or k1, k2, ... with a prefix); nil stays nil."""
    labels = {}

    def label(raw):
        if raw == "nil":
            return raw
        if raw not in labels:
            n = len(labels)
            labels[raw] = f"{prefix}{n + 1}" if prefix else chr(65 + n % 26) + (str(n // 26) if n >= 26 else "")
        return labels[raw]
    label.labels = labels
    return label


class Timeline:
    def __init__(self):
        self.char, self.rkey, self.out, self.batch, self.at = labeller(), labeller("k"), [], None, None
        self.seen, self.present, self.last_items, self.last_entries, self.seeds = {}, set(), {}, {}, {}

    def add(self, u, step, kind, rest):
        if (u, step) != self.at:
            self.flush()
            self.at, self.batch = (u, step), {k: [] for k in ("PLAYER", "PLAYERX", "ROSTER", "ENTRY", "COUNT")}
        self.batch[kind].append(rest)

    def players(self, rows):
        out, present = [], set()
        for r in rows:
            m = PLAYER.match(r)
            if not m:
                out.append("?" + r)
                continue
            i, t, seed, ptr, parent, counts, a0, a1, a2 = m.groups()
            lab = self.char(ptr)
            present.add(lab)
            self.seeds[lab] = seed
            c = counts.split()
            items = {c[k]: int(c[k + 1]) for k in range(0, len(c) - 1, 2)}
            self.last_items[lab] = items
            held = " ".join(k if n == 1 else f"{k}x{n}" for k, n in items.items() if n)
            out.append(f"P{i} t{t} {lab}{' parent' if parent == 'true' else ''} [{held}] act {a0}/{a1}/{a2}")
        return out, present

    def roster(self, rows):
        out = []
        for m in filter(None, map(ROSTER.match, rows)):
            key, num, sw, partner, left, typ, grp = m.groups()
            flags = (" sw" if sw == "true" else "") + (f" p={self.rkey(partner)}" if partner != "nil" else "") \
                + (" left" if left == "true" else "") + (f" t{typ} g{grp}" if typ is not None else "")
            out.append(f"{self.rkey(key)}#{num}{flags}")
        return out

    def entries(self, rows):
        groups, entries = {}, {}
        for m in filter(None, map(ENTRY.match, rows)):
            cid, owner, floor, merged, temporary = m.groups()
            lab = self.rkey(owner)
            tok = "c" + cid + ("*merged" if merged == "true" else "") + ("(temp)" if temporary == "true" else "")
            groups.setdefault(f"{lab}[{floor}]", []).append(tok)
            entries.setdefault(lab, {}).setdefault("c" + cid, 0)
            entries[lab]["c" + cid] += 1
        self.last_entries = entries
        return "  ".join(f"{k}: {' '.join(v)}" for k, v in groups.items())

    def flush(self):
        if not self.batch:
            return
        b, (u, step) = self.batch, self.at
        players, present = self.players(b["PLAYER"])
        for lab in sorted(present - self.present):
            self.seen[lab] = self.seen.get(lab, []) + [(u, "back" if lab in self.seen else "appeared")]
        for lab in sorted(self.present - present):
            self.seen.setdefault(lab, []).append((u, "gone"))
        self.present = present
        self.out.append(f"u{u:<4} {step:<24} | {' | '.join(players)} || roster {' '.join(self.roster(b['ROSTER']))} || {self.entries(b['ENTRY'])}")
        self.out += [f"       {kind} {r}" for kind in ("PLAYERX", "COUNT") for r in b[kind]]
        self.batch = None

    def note(self, text):
        self.flush()
        self.out.append("       " + text)

    def summary(self):
        self.flush()
        rows = []
        for ptr, lab in self.char.labels.items():
            hist = ", ".join(f"{what} u{u}" for u, what in self.seen.get(lab, []))
            items = " ".join(f"{k}x{n}" for k, n in self.last_items.get(lab, {}).items() if n) or "-"
            rows.append(f"    {lab} = hash {ptr} seed {self.seeds.get(lab)}: {hist}; {'present' if lab in self.present else 'absent'} at the end; engine {items}")
        for key, lab in self.rkey.labels.items():
            ent = " ".join(f"{k}x{n}" for k, n in self.last_entries.get(lab, {}).items()) or "-"
            rows.append(f"    {lab} = ReHUD key {key}: entries {ent}")
        return rows


def timeline(t):
    tl = Timeline()
    for raw in t.lines:
        m = PROBE.search(raw)
        text = m.group(1) if m else ""
        o, st = TRACE.match(text), TRACE_STEP.match(text)
        if o:
            tl.add(int(o.group(1)), o.group(2), o.group(3), o.group(4))
        elif st:
            tl.note(f"-- step {st.group(2)} (u{st.group(1)})")
        elif text.startswith(("INFO ", "SWAP ", "CMD ", "ASSERT FAIL", "GAME START")):
            tl.note(text)
    summary = tl.summary()  # first: it flushes the last update into tl.out
    return [f"== {t.key}"] + tl.out + [f"  summary {t.key}: {t.status or 'no RESULT: log ends mid-test'}"] + summary


def find_test(s, name):
    return next((t for t in s.tests.values() if name in (t.key, t.name)), None)


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("log")
    ap.add_argument("--out", help="folder for traces/ and report.json (default: the log's folder)")
    ap.add_argument("--specs", default=os.path.join(HERE, "..", "specs"), help="folder of the <spec>.snap.txt files")
    ap.add_argument("--timeline", help="a test, '<spec> > <test>' or its name, to print as a timeline")
    args = ap.parse_args(argv)
    sys.stdout.reconfigure(errors="replace")  # a console code page (cp1251) cannot print every mod's text (B5)
    out_dir = args.out or os.path.dirname(os.path.abspath(args.log))
    reader = Reader()
    with open(args.log, encoding="utf-8", errors="replace") as f:
        for raw in f:
            reader.feed(raw)
    s = reader.finish()
    # shortcut: HARNESS START carries no clock, so the session time is the log's last write; log it in HARNESS START if copies blur it.
    s.start = datetime.datetime.fromtimestamp(os.path.getmtime(args.log)).isoformat(timespec="seconds")
    apply_snapshots(s, args.specs)
    write_traces(s, out_dir)
    reasons = session_reasons(s)
    lines = report_lines(s, reasons)
    if args.timeline:
        t = find_test(s, args.timeline)
        lines = (timeline(t) if t else [f"no test {args.timeline!r} in the log"]) + [""] + lines
    with open(os.path.join(out_dir, "report.json"), "w", encoding="utf-8") as f:
        json.dump(report_json(s, reasons), f, indent=1, ensure_ascii=False)
    print("\n".join(lines))
    return 0 if not reasons else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
