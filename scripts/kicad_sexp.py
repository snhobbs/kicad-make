"""Read, edit and write KiCad S-expression files without disturbing the rest of the file."""
import re

from sexpdata import Parser, Symbol, dumps

NODE_NAME = re.compile(r"\(\s*([^\s()]+)")


class VerbatimParser(Parser):
    """Keep every atom as written, so numbers like 12.000000 aren't reformatted."""

    def atom(self, token):
        return Symbol(token)


def load(text: str) -> list:
    return VerbatimParser(text, nil=None, true=None, false=None,
                          line_comment="\0").parse()[0]


def dump(node, depth: int = 0) -> str:
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


def num(value: float) -> Symbol:
    return Symbol(f"{value:.6f}".rstrip("0").rstrip("."))


def is_node(item, name: str) -> bool:
    return isinstance(item, list) and bool(item) and item[0] == Symbol(name)


def child(node: list, name: str) -> list | None:
    return next((item for item in node if is_node(item, name)), None)


def set_child(node: list, name: str, value, after: str) -> None:
    """Set (name value) in node, adding it after the last `after` child if missing."""
    existing = child(node, name)
    if existing:
        existing[1:] = [value]
        return
    index = max((i for i, item in enumerate(node) if is_node(item, after)), default=0)
    node.insert(index + 1, [Symbol(name), value])


def child_spans(text: str, start: int, end: int) -> dict[str, tuple[int, int]]:
    """Text spans of the direct child nodes of the node at text[start:end], by name."""
    spans = {}
    depth = 0
    in_string = False
    child_start = start
    i = start
    while i < end:
        char = text[i]
        if in_string:
            if char == "\\":
                i += 1
            elif char == '"':
                in_string = False
        elif char == '"':
            in_string = True
        elif char == "(":
            depth += 1
            if depth == 2:
                child_start = i
        elif char == ")":
            if depth == 2:
                spans.setdefault(NODE_NAME.match(text, child_start).group(1), (child_start, i + 1))
            depth -= 1
        i += 1
    return spans


def replace_top_level(text: str, board: list, names: list[str]) -> str:
    """Re-dump only the named top-level nodes of `board` into the original text."""
    spans = child_spans(text, 0, len(text))
    edits = sorted(((spans[name], dump(child(board, name), 1)) for name in names), reverse=True)
    for (start, end), replacement in edits:
        text = text[:start] + replacement + text[end:]
    return text
