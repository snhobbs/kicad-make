#!/usr/bin/env python3
"""Set the vias on a board to the default sizes of a vias profile.

  via_defaults.py board.kicad_pcb [--vias fr4-blind] [--write]

Each via is sized by what it connects, using fab-settings/vias/<profile>.yaml:
  through (outer layer to outer layer)      first entry of `sizes`
  outer layer to the next layer             `microvia`, and the via becomes a micro via
  on a `through_nets` net (GND)             always through, whatever it was
  anything else (skip-layer blind, buried)  left alone and listed: they have no default
                                            size in the profile and need rerouting
Vias are edited in place by splicing the text, nothing else in the file changes.
Dry run by default; --write saves the board and keeps a .bak copy.
"""
import argparse
import re
import shutil
import sys
from collections import Counter
from pathlib import Path

from fab_settings import SettingsError, copper_names, load_setting
from kicad_sexp import num

VIA = re.compile(r"\n\t\(via\b.*?\n\t\)", re.S)
NUM = r"-?\d+(?:\.\d+)?"


def board_coppers(text: str) -> list[str]:
    """Copper layers from the board's layer table, outermost first."""
    table = re.search(r"\(layers\s(.*?)\n\t\)", text, re.S).group(1)
    names = re.findall(r'\(\d+ "([^"]+\.Cu)"', table)
    return names or copper_names(2)


def classify(layers: tuple[str, str], coppers: list[str]) -> str:
    a, b = sorted(coppers.index(name) for name in layers)
    last = len(coppers) - 1
    if (a, b) == (0, last):
        return "through"
    if a == 0 and b == 1 or a == last - 1 and b == last:
        return "micro"
    return "blind" if a == 0 or b == last else "buried"


def resize(via: str, diameter: float, drill: float, micro: bool,
           layers: tuple[str, str] | None = None) -> str:
    if layers:
        via = re.sub(r'\(layers "[^"]+" "[^"]+"\)', f'(layers "{layers[0]}" "{layers[1]}")', via,
                     count=1)
    via = re.sub(rf"\(size {NUM}\)", f"(size {num(diameter)})", via, count=1)
    via = re.sub(rf"\(drill {NUM}\)", f"(drill {num(drill)})", via, count=1)
    head = re.match(r"\n\t\(via(?: (?:micro|blind|buried))?", via)
    return f"\n\t(via{' micro' if micro else ''}" + via[head.end():]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("pcb", type=Path)
    ap.add_argument("--vias", default="fr4-blind", help="profile name or .yaml path")
    ap.add_argument("--write", action="store_true", help="save changes (default: dry run)")
    args = ap.parse_args()

    try:
        profile = load_setting("vias", args.vias)
    except SettingsError as error:
        sys.exit(f"via_defaults: {error}")
    text = args.pcb.read_text(encoding="utf-8")
    coppers = board_coppers(text)
    through = profile.sizes[0]

    changed, left = Counter(), Counter()
    unchanged_at = Counter()

    def fix(match: re.Match) -> str:
        via = match.group()
        layers = re.search(r'\(layers "([^"]+)" "([^"]+)"\)', via).groups()
        kind = classify(layers, coppers)
        net = re.search(r'\(net "([^"]*)"\)', via)
        if net and net.group(1) in profile.through_nets and kind != "through":
            kind, layers = "to-through", (coppers[0], coppers[-1])
            target = through
        elif kind == "through":
            target = through
        elif kind == "micro" and profile.microvia:
            target = profile.microvia
        else:
            left[(kind, layers, *re.findall(rf"\((?:size|drill) ({NUM})\)", via)[:2])] += 1
            return via
        new = resize(via, target.diameter, target.drill, micro=kind == "micro",
                     layers=layers if kind == "to-through" else None)
        if new != via:
            changed[(kind, target.diameter, target.drill)] += 1
        return new

    out = VIA.sub(fix, text)
    print(f"{args.pcb.name}: {sum(changed.values())} vias resized to {profile.name}")
    for (kind, diameter, drill), count in sorted(changed.items()):
        print(f"  {count:4} {kind:8} -> {diameter}/{drill}")
    if left:
        print(f"  left alone, no default size in the profile ({sum(left.values())}):")
        for (kind, layers, size, drill), count in sorted(left.items()):
            print(f"  {count:4} {kind:8} {layers[0]}-{layers[1]} {size}/{drill}")

    if not args.write:
        print("dry run; re-run with --write to apply")
    elif out != text:
        shutil.copy2(args.pcb, args.pcb.with_suffix(args.pcb.suffix + ".bak"))
        args.pcb.write_text(out, encoding="utf-8")
        print(f"wrote {args.pcb} (backup: {args.pcb.name}.bak)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
