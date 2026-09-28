#!/usr/bin/env python3
"""Write a copy of a .kicad_pcb with its stackup recoloured for 3D renders.

kicad-cli's --use-board-stackup-colors takes the solder mask, silkscreen and
copper finish from the board stackup, so editing those in a throwaway copy
is the only way to change how a render looks without touching the board.
"""
import argparse
import sys

from sexpdata import Parser, Symbol, dumps


class VerbatimParser(Parser):
    """Keep every atom as written, so numbers like 12.000000 aren't reformatted."""

    def atom(self, token):
        return Symbol(token)


def load(text):
    return VerbatimParser(text, nil=None, true=None, false=None,
                          line_comment="\0").parse()[0]


def dump(node, depth=0):
    """Format like KiCad: leading atoms on the opening line, then one item per line."""
    if not isinstance(node, list):
        return dumps(node)
    first_list = next((i for i, item in enumerate(node) if isinstance(item, list)), len(node))
    text = "(" + " ".join(dump(item) for item in node[:first_list])
    if first_list == len(node):
        return text + ")"
    indent = "\t" * (depth + 1)
    text += "".join(f"\n{indent}{dump(item, depth + 1)}" for item in node[first_list:])
    return text + "\n" + "\t" * depth + ")" + ("\n" if depth == 0 else "")


def is_node(item, name):
    return isinstance(item, list) and item and item[0] == Symbol(name)


def child(node, name):
    return next((item for item in node if is_node(item, name)), None)


def set_child(node, name, value, after):
    """Set (name value) in node, adding it after the last `after` child if missing."""
    existing = child(node, name)
    if existing:
        existing[1:] = [value]
        return
    index = max((i for i, item in enumerate(node) if is_node(item, after)), default=len(node) - 1)
    node.insert(index + 1, [Symbol(name), value])


def set_layer_colors(stackup, layer_suffix, color):
    """Set (color ...) on every stackup layer whose name ends in layer_suffix."""
    for layer in stackup:
        if is_node(layer, "layer") and layer[1].endswith("." + layer_suffix):
            set_child(layer, "color", color, after="type")


def apply_preset(board, mask=None, silk=None, finish=None):
    setup = child(board, "setup")
    stackup = child(setup, "stackup") if setup else None
    if not stackup:
        print("render_preset: board has no stackup, colours unchanged "
              "(add one in Board Setup > Physical Stackup)", file=sys.stderr)
        return
    if mask:
        set_layer_colors(stackup, "Mask", mask)
    if silk:
        set_layer_colors(stackup, "SilkS", silk)
    if finish:
        set_child(stackup, "copper_finish", finish, after="layer")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("board", help="input .kicad_pcb")
    parser.add_argument("output", help="output .kicad_pcb")
    parser.add_argument("--mask", help='solder mask colour, "#RRGGBBAA" or a KiCad name')
    parser.add_argument("--silk", help='silkscreen colour, "#RRGGBBAA" or a KiCad name')
    parser.add_argument("--finish", help='copper finish, e.g. "ENIG", "HAL lead-free"')
    args = parser.parse_args()

    with open(args.board, encoding="utf-8") as f:
        board = load(f.read())
    apply_preset(board, args.mask, args.silk, args.finish)
    with open(args.output, "w", encoding="utf-8") as f:
        f.write(dump(board))


if __name__ == "__main__":
    main()
