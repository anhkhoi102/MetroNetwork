#!/usr/bin/env python3
"""Translation housekeeping for Metro Network (see MetroNetwork/UI/L10n.swift).

  Scripts/l10n.py check   lists every English string that has no Vietnamese translation
  Scripts/l10n.py keys    prints the missing keys as JSON, for translating
  Scripts/l10n.py wrap    puts tr(...) around app string literals that are built with \\( ) or +
                          (core files are never rewritten: their text is looked up as a whole)

A string literal "Deliver \\(n) passengers" has the key "Deliver %@ passengers". Plain literals shown through
Text(), Button() or Label() need no tr(): those look the string up themselves.
"""
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "MetroNetwork")
CORE = os.path.join(ROOT, "Packages/MetroCore/Sources/MetroCore")
TABLE = os.path.join(APP, "Resources/Localization/vi.json")
APP_SOURCES = sorted(glob.glob(os.path.join(APP, "UI/*.swift")) + glob.glob(os.path.join(APP, "Game/*.swift"))
                     + [os.path.join(APP, "App/RootView.swift")])
APP_SOURCES = [s for s in APP_SOURCES if not s.endswith(("L10n.swift", "VisualTheme.swift"))]
# Core files with text the player reads (scenario briefings, error messages, display names).
CORE_SOURCES = [os.path.join(CORE, p) for p in [
    "Engine/CampaignManager.swift", "Engine/GameCommand.swift", "Model/Difficulty.swift", "Model/Station.swift",
    "Model/MapDefinition.swift"]]
SOURCES = APP_SOURCES + CORE_SOURCES
# Lines whose strings are not for the player.
SKIP_LINE = re.compile(r"forResource|withExtension|appendingPathComponent|hasPrefix|forKey|"
                       r"fontNamed|environment\[|MapPreset\(id:|case \.\w+: \"[a-z]|"
                       r"assertionFailure|fatalError|\.named\(|ThemePalette\(|accessibilityIdentifier|rawValue|"
                       r"\"[A-Z]{2}\"|ImageResource|Image\(\"")
# Functions that show a string without looking it up: a plain literal handed to them needs tr().
NEEDS_TR = (".help(", "confirmationDialog(", "showToast(", ".accessibilityLabel(", "Toggle(")
# Literals that are ids, symbols or names, not text.
IDENTIFIERS = {"Logo", "Outfit", "English", "Tiếng Việt", "EN", "VI", "Metro Network", "fit", "waiting", "trip", "load",
               "crowding", "map", "infinity", "gearshape", "xmark", "medal", "star", "rush", "clock",
               "campaign", "challenges", "endless", "statistics", "settings"}
# SF Symbol names passed as systemImage:/systemName: are not text.
SYMBOL = re.compile(r"(systemImage|systemName|icon|systemImageName)\s*:\s*$")
# City names stay as they are.
NAMES = {"Millbrook", "Riverside", "Westhaven", "Harbour Bay", "Twin Lakes", "Old Port", "Grand Central", "Twofold",
         "Commuter Belt", "Fixed Fleet", "Archipelago", "Mayhem", "Lakeland", "Twin Rivers"}
# Display names the app composes from data (theme names, line colours).
EXTRA = ["Metropolitan", "Coastal", "Old Town", "Industrial", "Crimson", "Amber", "Azure", "Emerald", "Violet", "Rose",
         "Teal", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]


class Literal:
    def __init__(self, start):
        self.start = start
        self.end = start
        self.segments = [""]
        self.nested = []

    @property
    def key(self):
        return "%@".join(self.segments)

    @property
    def interpolated(self):
        return len(self.segments) > 1

    @property
    def has_words(self):
        return any(re.search(r"[A-Za-z]{2,}", s) for s in self.segments)

    @property
    def is_identifier(self):
        key = self.key
        return key in IDENTIFIERS or key in NAMES or (" " not in key and (key.startswith("-") or re.search(r"[a-z0-9][_\-:#.][a-z0-9%]", key) is not None))


def parse_literal(src, i):
    """src[i] is the opening quote. Returns the literal; its end is one past the closing quote."""
    lit = Literal(i)
    i += 1
    while i < len(src):
        c = src[i]
        if c == "\\":
            if src[i + 1] == "(":
                i, inner = parse_code(src, i + 2, until_paren=True)
                lit.nested += inner
                lit.segments.append("")
                continue
            escapes = {"n": "\n", "t": "\t", '"': '"', "\\": "\\"}
            if src[i + 1] == "u":
                close = src.index("}", i)
                lit.segments[-1] += chr(int(src[i + 3:close], 16))
                i = close + 1
                continue
            lit.segments[-1] += escapes.get(src[i + 1], src[i + 1])
            i += 2
            continue
        if c == '"':
            lit.end = i + 1
            return lit
        lit.segments[-1] += c
        i += 1
    raise ValueError("unterminated string")


def parse_code(src, i, until_paren=False):
    """Scans code from i. Returns (index after, literals found). With until_paren, stops after the matching ')'."""
    found = []
    depth = 0
    while i < len(src):
        c = src[i]
        if src.startswith("//", i):
            i = src.find("\n", i)
            if i < 0:
                i = len(src)
            continue
        if src.startswith("/*", i):
            i = src.index("*/", i) + 2
            continue
        if c == '"':
            lit = parse_literal(src, i)
            found.append(lit)
            found += lit.nested
            i = lit.end
            continue
        if c == "(":
            depth += 1
        elif c == ")":
            if until_paren and depth == 0:
                return i + 1, found
            depth -= 1
        i += 1
    return i, found


def line_of(src, offset):
    return src.count("\n", 0, offset) + 1


def line_text(src, offset):
    start = src.rfind("\n", 0, offset) + 1
    end = src.find("\n", offset)
    return src[start:end if end >= 0 else len(src)]


def literals(path):
    src = open(path, encoding="utf-8").read()
    _, found = parse_code(src, 0)
    return src, [l for l in found if l.has_words and not l.is_identifier and not SKIP_LINE.search(line_text(src, l.start))
                 and not SYMBOL.search(src[max(0, l.start - 40):l.start])
                 and not re.search(r"(Image|symbol)\(\s*$", src[max(0, l.start - 20):l.start])]


def wrapped(src, lit):
    return src[:lit.start].rstrip().endswith("tr(")


def wants_tr(src, lit):
    before = src[:lit.start].rstrip()
    after = src[lit.end:].lstrip()
    return (lit.interpolated or before.endswith("+") or after.startswith("+")
            or src[:lit.start].endswith(NEEDS_TR))


def all_keys():
    keys = {}
    for path in SOURCES:
        src, found = literals(path)
        for lit in found:
            keys.setdefault(lit.key, f"{os.path.basename(path)}:{line_of(src, lit.start)}")
    for text in EXTRA:
        keys.setdefault(text, "app data")
    return keys


def table():
    return json.load(open(TABLE, encoding="utf-8")) if os.path.exists(TABLE) else {}


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "check"
    if mode == "wrap":
        dry = "--dry" in sys.argv
        for path in APP_SOURCES:
            src, found = literals(path)
            todo = [l for l in found if wants_tr(src, l) and not wrapped(src, l)]
            for lit in sorted(todo, key=lambda l: l.start):
                print(f"{os.path.basename(path)}:{line_of(src, lit.start)}  {lit.key[:110]!r}")
            # A literal can sit inside another: put every piece in by position, from the back.
            inserts = [(l.start, "tr(") for l in todo] + [(l.end, ")") for l in todo]
            for position, piece in sorted(inserts, key=lambda pair: -pair[0]):
                src = src[:position] + piece + src[position:]
            if not dry:
                open(path, "w", encoding="utf-8").write(src)
    elif mode == "keys":
        have = table()
        print(json.dumps({k: "" for k in all_keys() if k not in have}, ensure_ascii=False, indent=0))
    else:
        have = table()
        missing = {k: where for k, where in all_keys().items() if k not in have}
        for key, where in missing.items():
            print(f"{where}: {key!r}")
        unused = [k for k in have if k not in all_keys()]
        print(f"{len(missing)} without a translation, {len(have)} translated, {len(unused)} in the tables but not in the game")
        if "--unused" in sys.argv:
            for key in unused:
                print(f"unused: {key!r}")
        sys.exit(1 if missing else 0)


if __name__ == "__main__":
    main()
