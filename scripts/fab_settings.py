#!/usr/bin/env python3
"""Apply fab settings (stackup, colours, design rules) to a KiCad board.

Settings live in fab-settings/ as three independent sets of YAML files:
  stackups/  physical build: copper, dielectrics, mask thickness, board colour
  colors/    solder mask and silkscreen colours, copper finish
  rules/     fab design rule minimums, default net class, solder mask settings
plus sizes.yaml, the predefined track widths added with every stackup.
kicad-setting-boards/ has the template boards made from them.

  fab_settings.py list
  fab_settings.py apply board.kicad_pcb --stackup jlcpcb-4l-fr4-1.6mm --colors green \\
      --rules jlcpcb-4l
  fab_settings.py templates kicad-setting-boards/templates.yaml  # for Import Settings

Stackups and colours edit the .kicad_pcb, rules edit the .kicad_pcb and its
.kicad_pro. Only the edited settings change, so the board diffs cleanly.
"""
import argparse
import json
import re
import shutil
import sys
from dataclasses import dataclass, fields
from pathlib import Path

import yaml
from sexpdata import Symbol

from kicad_sexp import child, dump, is_node, load, num, replace_top_level, set_child
from microstrip import width_for_impedance

SETTINGS_DIR = Path(__file__).resolve().parent.parent / "fab-settings"
KINDS = ("stackups", "colors", "rules")
DIELECTRIC_TYPES = ("core", "prepreg")
# Board fab settings in the stackup that aren't part of a fab's stackup
KEPT_STACKUP_SETTINGS = ("dielectric_constraints", "edge_connector", "castellated_pads",
                         "edge_plating")


class SettingsError(Exception):
    pass


def check_keys(data: dict, allowed: set[str]) -> None:
    unknown = set(data) - allowed
    if unknown:
        raise SettingsError(f"unknown keys {', '.join(sorted(unknown))}")


# --- Stackups ---------------------------------------------------------------

@dataclass(frozen=True)
class SolderMask:
    thickness: float
    material: str
    epsilon_r: float
    loss_tangent: float


@dataclass(frozen=True)
class Copper:
    thickness: float


@dataclass(frozen=True)
class Dielectric:
    type: str
    thickness: float
    material: str
    epsilon_r: float
    loss_tangent: float
    color: str | None = None


@dataclass(frozen=True)
class Stackup:
    name: str
    description: str
    solder_mask: SolderMask
    layers: tuple[Copper | Dielectric, ...]
    # Top layer trace widths from the fab's impedance calculator, by ohms,
    # used instead of the computed microstrip width
    impedance_widths: dict[int, float]

    @property
    def copper_count(self) -> int:
        return sum(isinstance(layer, Copper) for layer in self.layers)

    @property
    def thickness(self) -> float:
        return 2 * self.solder_mask.thickness + sum(layer.thickness for layer in self.layers)

    def top_trace_width(self, ohms: int) -> float:
        if ohms in self.impedance_widths:
            return self.impedance_widths[ohms]
        copper, dielectric = self.layers[0], self.layers[1]
        return width_for_impedance(ohms, dielectric.thickness, copper.thickness,
                                   dielectric.epsilon_r)


def parse_layer(index: int, item: dict) -> Copper | Dielectric:
    if not isinstance(item, dict) or len(item) != 1:
        raise SettingsError(f"layers[{index}]: expected one of copper/core/prepreg, got {item!r}")
    (kind, value), = item.items()
    if kind == "copper":
        return Copper(thickness=float(value))
    if kind in DIELECTRIC_TYPES:
        return Dielectric(type=kind, **value)
    raise SettingsError(f"layers[{index}]: unknown layer kind {kind!r}")


def parse_stackup(data: dict) -> Stackup:
    check_keys(data, {"name", "description", "source", "solder_mask", "impedance_widths",
                      "layers"})
    layers = tuple(parse_layer(i, item) for i, item in enumerate(data["layers"]))
    if len(layers) < 3 or any(isinstance(layer, Copper) != (i % 2 == 0)
                              for i, layer in enumerate(layers)) or len(layers) % 2 == 0:
        raise SettingsError("layers must alternate copper/dielectric, starting and ending with copper")
    stackup = Stackup(
        name=data["name"],
        description=data.get("description", ""),
        solder_mask=SolderMask(**data["solder_mask"]),
        layers=layers,
        impedance_widths={int(k): float(v) for k, v in data.get("impedance_widths", {}).items()},
    )
    if stackup.copper_count % 2:
        raise SettingsError("KiCad boards need an even number of copper layers")
    return stackup


# --- Colours ----------------------------------------------------------------

@dataclass(frozen=True)
class Colors:
    """Colours are KiCad names or "#RRGGBBAA"; None leaves the board's setting."""
    name: str = ""
    description: str = ""
    solder_mask: str | None = None
    silkscreen: str | None = None
    copper_finish: str | None = None


def parse_colors(data: dict) -> Colors:
    check_keys(data, {field.name for field in fields(Colors)})
    return Colors(**data)


# --- Rules ------------------------------------------------------------------

@dataclass(frozen=True)
class Constraints:
    """Board Setup > Constraints, written to the .kicad_pro under the same names."""
    min_clearance: float
    min_track_width: float
    min_connection: float
    min_via_diameter: float
    min_via_annular_width: float
    min_through_hole_diameter: float
    min_hole_to_hole: float
    min_hole_clearance: float
    min_copper_edge_clearance: float
    min_text_height: float
    min_text_thickness: float


@dataclass(frozen=True)
class NetClass:
    """Board Setup > Net Classes, Default class."""
    clearance: float
    track_width: float
    via_diameter: float
    via_drill: float


@dataclass(frozen=True)
class MaskRules:
    """Board Setup > Solder Mask/Paste, stored in the .kicad_pcb."""
    expansion: float
    min_web: float


@dataclass(frozen=True)
class Rules:
    name: str
    description: str
    constraints: Constraints
    default_netclass: NetClass
    solder_mask: MaskRules


def parse_rules(data: dict) -> Rules:
    check_keys(data, {"name", "description", "source", "constraints", "default_netclass",
                      "solder_mask"})
    return Rules(
        name=data["name"],
        description=data.get("description", ""),
        constraints=Constraints(**data["constraints"]),
        default_netclass=NetClass(**data["default_netclass"]),
        solder_mask=MaskRules(**data["solder_mask"]),
    )


# --- Predefined sizes ---------------------------------------------------------

@dataclass(frozen=True)
class Sizes:
    track_widths: tuple[float, ...]
    impedances: tuple[int, ...]


def load_sizes() -> Sizes:
    with open(SETTINGS_DIR / "sizes.yaml", encoding="utf-8") as f:
        data = yaml.safe_load(f)
    return Sizes(track_widths=tuple(float(w) for w in data["track_widths"]),
                 impedances=tuple(int(z) for z in data["impedances"]))


# --- Loading ----------------------------------------------------------------

PARSERS = {"stackups": parse_stackup, "colors": parse_colors, "rules": parse_rules}


def available(kind: str) -> list[str]:
    return sorted(path.stem for path in (SETTINGS_DIR / kind).glob("*.yaml"))


def load_setting(kind: str, name: str):
    """Load a stackup, colours or rules file by name, or from a path to a .yaml file."""
    path = Path(name)
    if path.suffix not in (".yaml", ".yml"):
        path = SETTINGS_DIR / kind / f"{name}.yaml"
        if not path.exists():
            raise SettingsError(f"no {kind} {name!r}, available: {', '.join(available(kind))}")
    with open(path, encoding="utf-8") as f:
        data = yaml.safe_load(f)
    try:
        return PARSERS[kind](data)
    except (KeyError, TypeError, ValueError, SettingsError) as error:
        raise SettingsError(f"{path}: {error}") from error


# --- Board (.kicad_pcb) edits ------------------------------------------------

def copper_names(count: int) -> list[str]:
    return ["F.Cu", *(f"In{i}.Cu" for i in range(1, count - 1)), "B.Cu"]


def is_copper_entry(item) -> bool:
    return isinstance(item, list) and len(item) > 1 and str(item[1]).endswith(".Cu")


def inner_layer_id(board_layers: list, inner: int) -> int:
    """Layer table id for In{inner}.Cu: KiCad 9+ numbers them 4, 6, ...; earlier 1, 2, ..."""
    ids = {str(item[1]): int(str(item[0])) for item in board_layers[1:] if is_copper_entry(item)}
    return inner if ids.get("B.Cu") == 31 else 2 + 2 * inner


def used_layers(board: list, names: list[str]) -> list[str]:
    """Names from `names` that items are on: (layer "X") or (layers ... "X" ...)."""
    body = "\n".join(dump(item) for item in board[1:]
                     if not (is_node(item, "layers") or is_node(item, "setup")))
    return [name for name in names
            if re.search(rf'\(layers?\s[^()]*"{re.escape(name)}"', body)]


def set_copper_layers(board: list, count: int) -> None:
    board_layers = child(board, "layers")
    current = [str(item[1]) for item in board_layers[1:] if is_copper_entry(item)]
    wanted = copper_names(count)
    removed = [name for name in current if name not in wanted]
    in_use = used_layers(board, removed)
    if in_use:
        raise SettingsError(f"can't drop to {count} copper layers, these still have items: "
                            f"{', '.join(in_use)}")
    board_layers[1:] = [item for item in board_layers[1:]
                        if not (is_copper_entry(item) and str(item[1]) in removed)]
    b_cu = next(i for i, item in enumerate(board_layers)
                if is_copper_entry(item) and str(item[1]) == "B.Cu")
    board_layers[b_cu:b_cu] = [
        [Symbol(str(inner_layer_id(board_layers, i))), name, Symbol("signal")]
        for i, name in enumerate(wanted[1:-1], start=1) if name not in current]


def stackup_layer(stackup_node: list, name: str) -> list | None:
    return next((item for item in stackup_node[1:]
                 if is_node(item, "layer") and str(item[1]) == name), None)


def board_colors(stackup_node: list | None) -> Colors:
    """The colours and finish set in an existing board stackup."""
    if not stackup_node:
        return Colors()

    def value(node, name):
        found = child(node, name) if node else None
        return str(found[1]) if found else None

    return Colors(solder_mask=value(stackup_layer(stackup_node, "F.Mask"), "color"),
                  silkscreen=value(stackup_layer(stackup_node, "F.SilkS"), "color"),
                  copper_finish=value(stackup_node, "copper_finish"))


def merge_colors(base: Colors, override: Colors | None) -> Colors:
    if not override:
        return base
    return Colors(**{field.name: getattr(override, field.name) or getattr(base, field.name)
                     for field in fields(Colors)})


def build_stackup_node(stackup: Stackup, colors: Colors, keep: list) -> list:
    """The (stackup ...) node; `keep` holds non-layer settings to carry over."""
    mask = stackup.solder_mask

    def colored(node, color):
        return node + ([[Symbol("color"), color]] if color else [])

    def mask_layer(name, kind):
        return colored([Symbol("layer"), name, [Symbol("type"), kind]], colors.solder_mask) + [
            [Symbol("thickness"), num(mask.thickness)], [Symbol("material"), mask.material],
            [Symbol("epsilon_r"), num(mask.epsilon_r)],
            [Symbol("loss_tangent"), num(mask.loss_tangent)]]

    nodes = [
        colored([Symbol("layer"), "F.SilkS", [Symbol("type"), "Top Silk Screen"]],
                colors.silkscreen),
        [Symbol("layer"), "F.Paste", [Symbol("type"), "Top Solder Paste"]],
        mask_layer("F.Mask", "Top Solder Mask"),
    ]
    names = iter(copper_names(stackup.copper_count))
    dielectric_index = 0
    for layer in stackup.layers:
        if isinstance(layer, Copper):
            nodes.append([Symbol("layer"), next(names), [Symbol("type"), "copper"],
                          [Symbol("thickness"), num(layer.thickness)]])
            continue
        dielectric_index += 1
        nodes.append(colored(
            [Symbol("layer"), f"dielectric {dielectric_index}", [Symbol("type"), layer.type]],
            layer.color) + [
            [Symbol("thickness"), num(layer.thickness)], [Symbol("material"), layer.material],
            [Symbol("epsilon_r"), num(layer.epsilon_r)],
            [Symbol("loss_tangent"), num(layer.loss_tangent)]])
    nodes += [
        mask_layer("B.Mask", "Bottom Solder Mask"),
        [Symbol("layer"), "B.Paste", [Symbol("type"), "Bottom Solder Paste"]],
        colored([Symbol("layer"), "B.SilkS", [Symbol("type"), "Bottom Silk Screen"]],
                colors.silkscreen),
    ]
    if colors.copper_finish:
        nodes.append([Symbol("copper_finish"), colors.copper_finish])
    return [Symbol("stackup"), *nodes, *keep]


def set_board_thickness(board: list, thickness: float) -> None:
    general = child(board, "general")
    existing = child(general, "thickness")
    if existing:
        existing[1:] = [num(thickness)]
    else:
        general.insert(1, [Symbol("thickness"), num(thickness)])


def recolor_stackup(stackup_node: list, colors: Colors) -> None:
    for layer in stackup_node[1:]:
        if not is_node(layer, "layer"):
            continue
        name = str(layer[1])
        color = (colors.solder_mask if name.endswith(".Mask")
                 else colors.silkscreen if name.endswith(".SilkS") else None)
        if color:
            set_child(layer, "color", color, after="type")
    if colors.copper_finish:
        set_child(stackup_node, "copper_finish", colors.copper_finish, after="layer")


def apply_to_board(text: str, stackup: Stackup | None, colors: Colors | None,
                   rules: Rules | None) -> str:
    board = load(text)
    setup = child(board, "setup")
    old = child(setup, "stackup")
    edited = ["setup"]
    if stackup:
        set_copper_layers(board, stackup.copper_count)
        set_board_thickness(board, stackup.thickness)
        edited += ["layers", "general"]
        keep = [item for item in (old or [])[1:]
                if any(is_node(item, name) for name in KEPT_STACKUP_SETTINGS)]
        new = build_stackup_node(stackup, merge_colors(board_colors(old), colors), keep)
        if old:
            setup[setup.index(old)] = new
        else:
            setup.insert(1, new)
    elif colors:
        if not old:
            raise SettingsError("board has no stackup to colour, apply a --stackup first")
        recolor_stackup(old, colors)
    if rules:
        set_child(setup, "pad_to_mask_clearance", num(rules.solder_mask.expansion),
                  after="stackup")
        set_child(setup, "solder_mask_min_width", num(rules.solder_mask.min_web),
                  after="pad_to_mask_clearance")
    return replace_top_level(text, board, edited)


# --- Project (.kicad_pro) edits ----------------------------------------------

def predefined_track_widths(stackup: Stackup, sizes: Sizes, min_width: float) -> list[float]:
    widths = set(sizes.track_widths)
    for ohms in sizes.impedances:
        width = round(stackup.top_trace_width(ohms), 4)
        if width < min_width:
            print(f"fab_settings: {ohms} ohm top trace on {stackup.name} is {width} mm, "
                  f"under the {min_width} mm minimum, left out", file=sys.stderr)
            continue
        widths.add(width)
    return sorted(w for w in widths if w >= min_width)


def apply_to_project(project: dict, stackup: Stackup | None, rules: Rules | None,
                     sizes: Sizes) -> None:
    design = project["board"]["design_settings"]
    if rules:
        design["rules"].update(vars(rules.constraints))
        default = next(c for c in project["net_settings"]["classes"] if c["name"] == "Default")
        default.update(vars(rules.default_netclass))
    if stackup:
        min_width = design["rules"].get("min_track_width", 0)
        # The leading 0 is KiCad's "use net class width" entry
        design["track_widths"] = [0.0, *predefined_track_widths(stackup, sizes, min_width)]


def project_path(board: Path) -> Path:
    return board.with_suffix(".kicad_pro")


def apply(board: Path, output: Path, stackup: Stackup | None, colors: Colors | None,
          rules: Rules | None) -> None:
    text = apply_to_board(board.read_text(encoding="utf-8"), stackup, colors, rules)
    project = None
    if stackup or rules:
        if project_path(board).exists():
            project = json.loads(project_path(board).read_text(encoding="utf-8"))
            apply_to_project(project, stackup, rules, load_sizes())
        elif rules:
            raise SettingsError(f"rules go in {project_path(board)}, which doesn't exist")
    output.write_text(text, encoding="utf-8")
    if project is not None:
        project_path(output).write_text(json.dumps(project, indent=2) + "\n", encoding="utf-8")


# --- Template boards ---------------------------------------------------------

def write_templates(template_list: Path, out_dir: Path) -> None:
    """Boards from a template list, for Board Setup > Import Settings in KiCad."""
    import pcbnew

    with open(template_list, encoding="utf-8") as f:
        templates = yaml.safe_load(f)
    for name, parts in templates.items():
        stackup = load_setting("stackups", parts["stackup"])
        colors = load_setting("colors", parts["colors"])
        rules = load_setting("rules", parts["rules"])
        directory = out_dir / name
        shutil.rmtree(directory, ignore_errors=True)
        directory.mkdir(parents=True)
        board = directory / f"{name}.kicad_pcb"
        pcbnew.SaveBoard(str(board), pcbnew.NewBoard(str(board)))
        # Local view settings, not part of what Import Settings reads
        board.with_suffix(".kicad_prl").unlink(missing_ok=True)
        apply(board, board, stackup, colors, rules)
        print(f"fab_settings: {board}: {stackup.name}, {colors.name}, {rules.name}")


# --- CLI ---------------------------------------------------------------------

def list_settings() -> None:
    for kind in KINDS:
        print(f"{kind}:")
        for name in available(kind):
            setting = load_setting(kind, name)
            detail = (f"{setting.copper_count}L {setting.thickness:.3f} mm  "
                      if kind == "stackups" else "")
            print(f"  {name:22} {detail}{setting.description}")


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("list", help="list available stackups, colours and rules")
    apply_parser = commands.add_parser("apply", help="apply settings to a board")
    apply_parser.add_argument("board", type=Path, help=".kicad_pcb to edit in place")
    apply_parser.add_argument("-o", "--output", type=Path,
                              help="write here (and its .kicad_pro) instead of in place")
    for kind, flag in (("stackups", "--stackup"), ("colors", "--colors"), ("rules", "--rules")):
        apply_parser.add_argument(flag, dest=kind, help=f"name from fab-settings/{kind}/ "
                                  "or a path to a .yaml file")
    templates_parser = commands.add_parser("templates", help="write the boards in a template list")
    templates_parser.add_argument("list", type=Path,
                                  help="YAML of board name -> stackup, colors, rules")
    templates_parser.add_argument("-o", "--output", type=Path,
                                  help="directory to write to (default: the list's directory)")
    args = parser.parse_args()

    try:
        if args.command == "list":
            list_settings()
        elif args.command == "templates":
            write_templates(args.list, args.output or args.list.parent)
        else:
            chosen = {kind: load_setting(kind, getattr(args, kind))
                      for kind in KINDS if getattr(args, kind)}
            if not chosen:
                parser.error("give at least one of --stackup, --colors, --rules")
            apply(args.board, args.output or args.board, chosen.get("stackups"),
                  chosen.get("colors"), chosen.get("rules"))
            print(f"fab_settings: {args.output or args.board}: "
                  + ", ".join(setting.name for setting in chosen.values()))
    except SettingsError as error:
        sys.exit(f"fab_settings: {error}")


if __name__ == "__main__":
    main()
