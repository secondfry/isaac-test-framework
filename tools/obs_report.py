"""Timeline of the harness's obs scenarios: python -B -I tools/obs_report.py <log.txt>.

For each scenario whose name starts with "obs": one row per logged change (update, step, each player's type, seed label, items and
actives, ReHUD's roster and entries), the step starts, INFO lines and SWAP lines between them, then a summary per seed. Seeds are
shown as labels A, B, C... in first-seen order within the scenario. PLAYERX and COUNT lines print verbatim under their row.
"""
import re
import sys

PROBE = re.compile(r"(?:^|Lua Debug: )PROBE (.*)")
OBS = re.compile(r"OBS u(\d+) after (.*?): (PLAYER|PLAYERX|ROSTER|ENTRY|COUNT) (.*)")
STEP = re.compile(r"OBS u(\d+) step (.*) begins$")
PLAYER = re.compile(r"(\d+) type (\S+) seed (\S+) hash \S+ ctrl (\S+) parent (\S+) (.*) primary (\S+) secondary (\S+) pocket (\S+)$")
ROSTER = re.compile(r"key (\S+) number (\S+) swapped (\S+) partner (\S+) left (\S+)(?: type (\S+) group (\S+))?$")
ENTRY = re.compile(r"\d+ c(\d+) owner (\S+) floor (.*?)(?: merged (\S+) temporary (\S+))?$")


class Scenario:
    def __init__(self, name):
        self.name, self.labels, self.out, self.result = name, {}, [], None
        self.snap, self.u, self.step = None, None, None
        self.seen = {}  # label -> list of (update, "appeared"/"gone"/"back")
        self.present, self.last_items, self.last_entries = set(), {}, {}

    def label(self, seed):
        if seed == "nil":
            return seed
        if seed not in self.labels:
            n = len(self.labels)
            self.labels[seed] = chr(65 + n % 26) + (str(n // 26) if n >= 26 else "")
        return self.labels[seed]

    def add(self, u, step, kind, rest):
        if (u, step) != (self.u, self.step):
            self.flush()
            self.u, self.step, self.snap = u, step, {"PLAYER": [], "PLAYERX": [], "ROSTER": [], "ENTRY": [], "COUNT": []}
        self.snap[kind].append(rest)

    def flush(self):
        if not self.snap:
            return
        s, players, present, numbers = self.snap, [], set(), {}
        for r in s["ROSTER"]:
            m = ROSTER.match(r)
            if m:
                numbers[m.group(1)] = m.group(2)
        for r in s["PLAYER"]:
            m = PLAYER.match(r)
            if not m:
                players.append("?" + r)
                continue
            i, t, seed, ctrl, parent, counts, a0, a1, a2 = m.groups()
            lab = self.label(seed)
            present.add(lab)
            c = counts.split()
            items = {c[k]: int(c[k + 1]) for k in range(0, len(c) - 1, 2)}
            self.last_items[lab] = items
            held = " ".join(k if n == 1 else f"{k}x{n}" for k, n in items.items() if n)
            players.append(f"P{i} t{t} {lab}{' parent' if parent == 'true' else ''} [{held}] act {a0}/{a1}/{a2}")
        roster = []
        for r in s["ROSTER"]:
            m = ROSTER.match(r)
            if not m:
                continue
            key, num, sw, partner, left, typ, grp = m.groups()
            flags = (" sw" if sw == "true" else "") + (f" p={self.label(partner)}" if partner != "nil" else "") + (" left" if left == "true" else "") + (f" t{typ} g{grp}" if typ is not None else "")
            roster.append(f"{self.label(key)}#{num}{flags}")
        groups, entries = {}, {}
        for r in s["ENTRY"]:
            m = ENTRY.match(r)
            if not m:
                continue
            cid, owner, floor, merged, temporary = m.groups()
            lab = self.label(owner)
            tok = "c" + cid + ("*merged" if merged == "true" else "") + ("(temp)" if temporary == "true" else "")
            groups.setdefault(f"{lab}#{numbers.get(owner, '?')}[{floor}]", []).append(tok)
            entries.setdefault(lab, {}).setdefault("c" + cid, 0)
            entries[lab]["c" + cid] += 1
        self.last_entries = entries
        for lab in sorted(present - self.present):
            self.seen[lab] = self.seen.get(lab, []) + [(self.u, "back" if lab in self.seen else "appeared")]
        for lab in sorted(self.present - present):
            self.seen.setdefault(lab, []).append((self.u, "gone"))
        self.present = present
        ent = "  ".join(f"{k}: {' '.join(v)}" for k, v in groups.items())
        self.out.append(f"u{self.u:<4} {self.step:<24} | {' | '.join(players)} || roster {' '.join(roster)} || {ent}")
        for kind in ("PLAYERX", "COUNT"):
            self.out += [f"       {kind} {r}" for r in s[kind]]
        self.snap = None

    def note(self, s):
        self.flush()
        self.out.append("       " + s)

    def summary(self):
        self.flush()
        rows = [f"  summary {self.name}: {self.result}"]
        for seed, lab in self.labels.items():
            hist = ", ".join(f"{what} u{u}" for u, what in self.seen.get(lab, [])) or "never a player"
            items = " ".join(f"{k}x{n}" for k, n in self.last_items.get(lab, {}).items() if n) or "-"
            ent = " ".join(f"{k}x{n}" for k, n in self.last_entries.get(lab, {}).items()) or "-"
            rows.append(f"    {lab} = {seed}: {hist}; {'present' if lab in self.present else 'absent'} at the end; engine {items}; ReHUD entries {ent}")
        return rows


def report(lines):
    out, sc, names = [], None, []
    for raw in lines:
        m = PROBE.search(raw.rstrip("\r\n"))
        if not m:
            continue
        s = m.group(1)
        if s.startswith("SCENARIO START "):
            name = s[len("SCENARIO START "):]
            sc = Scenario(name) if name.startswith(("obs", "final ")) else None  # final: per-update OBS lines in F, G, I, J
            continue
        if not sc:
            continue
        if s.startswith("RESULT " + sc.name + " "):
            sc.result = s[len("RESULT " + sc.name + " "):]
            summary = sc.summary()  # first: it flushes the last update into sc.out
            out += [f"== {sc.name}"] + sc.out + summary + [""]
            names.append(sc.name)
            sc = None
            continue
        o, st = OBS.match(s), STEP.match(s)
        if o:
            sc.add(int(o.group(1)), o.group(2), o.group(3), o.group(4))
        elif st:
            sc.note(f"-- step {st.group(2)} (u{st.group(1)})")
        elif s.startswith(("INFO ", "SWAP ", "CMD ", "CHECK FAIL", "GAME START")):
            sc.note(s)
    if sc:  # a log cut off mid-scenario (crash, or read before the exit flushed it)
        sc.result = "no RESULT: log ends mid-scenario"
        summary = sc.summary()
        out += [f"== {sc.name}"] + sc.out + summary
        names.append(sc.name)
    out.append(f"obs scenarios: {len(names)} ({', '.join(names)})")
    return out


def main(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        print("\n".join(report(f.readlines())))


if __name__ == "__main__":
    main(sys.argv[1])
