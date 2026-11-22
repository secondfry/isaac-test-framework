"""Compact verdict on a harness run: python -B -I tools/run_report.py <log.txt>. Exit code 0 only on ALL PASS.

Reads log.txt (or the dry run's PROBE lines), prints each scenario's RESULT with its INFO answers, every CHECK FAIL with the lines
before it, the continues, and errors outside known noise, then one verdict line: ALL PASS or NEEDS ANALYSIS: <reasons>.
"""
import re
import sys

# Lines the error pattern matches that runs 6-8 showed to be benign, each with why.
NOISE = [
    "Different number of collectibles",  # engine [WARN] at every game start, harness or not (runs 6-8: 10-25 per run)
    "Could not find provider",  # Stats+ (WARN) at load: its essentials addon has no provider for three options; unrelated to ReHUD
]
# Case-sensitive, so the engine's lowercase "[warn] AnmCache" INFO lines (run 7, sprite cache on exit) stay out.
ERROR = re.compile(r'\[(WARN|ERROR)\]|\((WARN|ERROR)\)|\]ERROR:|Error in "|Lua stack trace|Caught exception|attempt to |Lua is resetting')
# Notes chance alone explains: the scenario could not reach a path this run. Any other note needs a look.
EXPLAINED = [
    "split (20 Clicker uses)",  # P2: Clicker rolls a random character and may never land on Jacob & Esau
    "Zodiac rolled the same item",  # S1b: the stage re-roll can repeat
    "3 Dollar Bill still grants",  # S1b: the next grant can roll the same item
    "no split in 12 Clicker uses",  # final G: Clicker lands on Jacob & Esau about 1 in 7
]
PROBE = re.compile(r"(?:^|Lua Debug: )PROBE (.*)")
RESULT = re.compile(r"RESULT (.+?) (PASS|FAIL|INFO|SKIP)\b(.*)")


def report(lines):
    out, reasons, errors = [], [], {}
    total, done, started, results = None, False, [], []
    seg, recent = [], []  # report lines since the last RESULT; the last probe lines, for CHECK FAIL context
    asks = resumed = 0
    for raw in lines:
        raw = raw.rstrip("\r\n")
        m = PROBE.search(raw)
        if not m:
            if ERROR.search(raw) and not any(n in raw for n in NOISE):
                key = re.sub(r"\d+", "N", raw)
                first, n = errors.get(key, (raw, 0))
                errors[key] = (first, n + 1)
            continue
        s = m.group(1)
        r = RESULT.match(s)
        if s.startswith("HARNESS START"):
            out.append(s)
            total = int(re.match(r"HARNESS START (\d+)", s).group(1))
        elif s == "HARNESS DONE":
            done = True
        elif s.startswith("HARNESS ERROR"):
            reasons.append(s)
        elif s.startswith("SCENARIO START "):
            started.append(s[len("SCENARIO START "):])
        elif s.startswith("CHECK FAIL"):
            seg.append("  " + s)
            seg.extend("      | " + c for c in recent[-4:])
        elif s.startswith("INFO "):
            seg.append(s)
        elif s.startswith("ACTION exit to the menu and Continue now by type"):
            asks += 1
            seg.append("  continue: asked")
        elif s.startswith("GAME START") and s.endswith("continued true"):
            seg.append("  continue: game continued")
        elif s.startswith("DONE exit to the menu and Continue now"):
            resumed += 1
            seg.append("  continue: resumed " + s.split("Continue now ", 1)[1])
        elif r:
            name, verdict, rest = r.groups()
            results.append(name)
            out.append(f"{name}: {verdict}{rest}")
            infos = {}
            for line in seg:
                if not line.startswith("INFO "):
                    out.append(line)
                    continue
                text = line[len("INFO " + name + " "):] if line.startswith("INFO " + name + " ") else line[5:]
                head, sep, tail = text.partition(": ")  # one row per answer: only a step number in the label ("after Clicker 3") folds
                key = re.sub(r"\d+", "N", head) + sep + tail if sep else text
                first, n = infos.get(key, (text, 0))
                infos[key] = (first, n + 1)
            out.extend(f"  info {t}" + (f" (x{n})" if n > 1 else "") for t, n in infos.values())
            seg = []
            if verdict == "FAIL":
                reasons.append(f"{name} FAIL")
            notes = rest.split("unobserved: ", 1)[1].split(", ") if "unobserved: " in rest else []
            odd = [n for n in notes if not any(n.startswith(e) for e in EXPLAINED)]
            if odd:
                reasons.append(f"{name} unobserved: {', '.join(odd)}")
        recent = (recent + [s])[-4:]
    out.extend(seg)  # lines after the last RESULT: a scenario cut off
    if errors:
        out.append("errors outside the noise list:")
        out.extend(f"  {raw}" + (f" (x{n})" if n > 1 else "") for raw, n in errors.values())
        reasons.append(f"{len(errors)} distinct errors")
    if total is None:
        reasons.append("no HARNESS START")
    elif len(results) != total:
        reasons.append(f"results for {len(results)} of {total} scenarios")
    if not done:
        reasons.append("no HARNESS DONE")
    lost = [n for n in started if n not in results]
    if lost:
        reasons.append("started without a result: " + ", ".join(lost))
    if asks != resumed:
        reasons.append(f"continue asked {asks} times, resumed {resumed}")
    out.append("ALL PASS" if not reasons else "NEEDS ANALYSIS: " + "; ".join(reasons))
    return out, not reasons


def main(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        out, ok = report(f)
    sys.stdout.reconfigure(errors="replace")
    print("\n".join(out))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
