#!/usr/bin/env python3
"""Apply fab settings (stackup, colours, design rules) to a KiCad board.

Settings live in fab-settings/ as four independent sets of YAML files:
  stackups/  physical build: copper, dielectrics, mask thickness, board colour
  colors/    solder mask and silkscreen colours, copper finish
  rules/     fab design rule minimums, default net class, solder mask settings
  vias/      via sizes and which kinds are allowed (through, blind, micro, buried)
plus sizes.yaml, the predefined track widths added with every stackup.
kicad-setting-boards/ has the template boards made from them.

  fab_settings.py list
  fab_settings.py apply board.kicad_pcb --stackup jlcpcb-4l-fr4-1.6mm --colors green \\
      --rules jlcpcb-4l --vias fr4-through
  fab_settings.py templates kicad-setting-boards/templates.yaml  # for Import Settings

Stackups and colours edit the .kicad_pcb, rules edit the .kicad_pcb and its
.kicad_pro, vias edit the .kicad_pro and the .kicad_dru (custom rules, only the
block this script owns). Only the edited settings change, so the board diffs cleanly.
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
KINDS = ("stackups", "colors", "rules", "vias")
DIELECTRIC_TYPES = ("core", "prepreg")
# The bottom's mask, paste and silkscreen, which a single-sided (metal core)
# board doesn't have, with their layer table ids (KiCad 9+, earlier) and the
# front layer each is listed after
BOTTOM_SIDE_LAYERS = {"B.Paste": (15, 34, "F.Paste"), "B.SilkS": (7, 36, "F.SilkS"),
                      "B.Mask": (3, 38, "F.Mask")}
BOTTOM_SIDE_USER_NAMES = {"B.SilkS": "B.Silkscreen"}
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
class Sublayer:
    """A further material in a dielectric layer, under its first one: the
    metal base of a metal core board, under the insulation."""
    thickness: float
    material: str
    epsilon_r: float
    loss_tangent: float
    color: str | None = None


@dataclass(frozen=True)
class Dielectric:
    type: str
    thickness: float  # of its first material, the one against the copper above
    material: str
    epsilon_r: float
    loss_tangent: float
    color: str | None = None
    sublayers: tuple[Sublayer, ...] = ()

    @property
    def total_thickness(self) -> float:
        return self.thickness + sum(sub.thickness for sub in self.sublayers)


@dataclass(frozen=True)
class Stackup:
    name: str
    description: str
    solder_mask: SolderMask
    layers: tuple[Copper | Dielectric, ...]
    # Top layer trace widths from the fab's impedance calculator, by ohms,
    # used instead of the computed microstrip width
    impedance_widths: dict[int, float]
    # Copper, mask and silkscreen on the top only (metal core): B.Cu is in the
    # board, as KiCad needs it, but has no thickness and nothing goes on it,
    # and the board has no bottom mask, paste or silkscreen layers
    single_sided: bool = False

    @property
    def copper_count(self) -> int:
        return sum(isinstance(layer, Copper) for layer in self.layers)

    @property
    def thickness(self) -> float:
        masks = 1 if self.single_sided else 2
        return masks * self.solder_mask.thickness + sum(
            layer.total_thickness if isinstance(layer, Dielectric) else layer.thickness
            for layer in self.layers)

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
        value = dict(value)
        sublayers = tuple(Sublayer(**sub) for sub in value.pop("sublayers", ()))
        return Dielectric(type=kind, sublayers=sublayers, **value)
    raise SettingsError(f"layers[{index}]: unknown layer kind {kind!r}")


def parse_stackup(data: dict) -> Stackup:
    check_keys(data, {"name", "description", "source", "solder_mask", "impedance_widths",
                      "single_sided", "layers"})
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
        single_sided=bool(data.get("single_sided", False)),
    )
    if stackup.copper_count % 2:
        raise SettingsError("KiCad boards need an even number of copper layers")
    if stackup.single_sided and (stackup.copper_count != 2 or layers[-1].thickness):
        raise SettingsError("a single_sided stackup is copper, dielectric and a bottom copper of 0")
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
    via_diameter: float | None = None  # left to a vias profile when absent
    via_drill: float | None = None


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


# --- Vias -------------------------------------------------------------------

@dataclass(frozen=True)
class ViaSize:
    diameter: float
    drill: float


@dataclass(frozen=True)
class Vias:
    """Via sizes and allowed kinds. `sizes` are Board Setup > Pre-defined Sizes, the
    first is the default net class via. `buried: false` is a custom DRC rule, KiCad
    has no setting for blind without buried."""
    name: str
    description: str
    sizes: tuple[ViaSize, ...]
    blind: bool
    buried: bool
    microvia: ViaSize | None
    through_nets: tuple[str, ...] = ()  # nets whose vias must go all the way through
    skip_vias: bool = True  # blind vias spanning more than one layer pair
    inner_microvias: bool = True  # microvias between two inner layers (not 1+N+1)


def parse_vias(data: dict) -> Vias:
    check_keys(data, {"name", "description", "source", "sizes", "blind", "buried", "microvia",
                      "through_nets", "skip_vias", "inner_microvias"})
    sizes = tuple(ViaSize(**size) for size in data["sizes"])
    if not sizes:
        raise SettingsError("sizes is empty")
    microvia = ViaSize(**data["microvia"]) if data.get("microvia") else None
    blind, buried = bool(data["blind"]), bool(data["buried"])
    if buried and not blind:
        raise SettingsError("buried vias need blind: true")
    for size in (*sizes, *([microvia] if microvia else [])):
        if size.drill >= size.diameter:
            raise SettingsError(f"via {size.diameter}/{size.drill}: drill must be under the pad")
    return Vias(name=data["name"], description=data.get("description", ""), sizes=sizes,
                blind=blind, buried=buried, microvia=microvia,
                through_nets=tuple(data.get("through_nets") or ()),
                skip_vias=bool(data.get("skip_vias", True)),
                inner_microvias=bool(data.get("inner_microvias", True)))


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

PARSERS = {"stackups": parse_stackup, "colors": parse_colors, "rules": parse_rules,
           "vias": parse_vias}


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


def set_bottom_side_layers(board: list, present: bool) -> None:
    """Take the bottom's mask, paste and silkscreen out of the layer table
    (a single-sided board: bare metal under it), or put them back."""
    board_layers = child(board, "layers")
    current = {str(item[1]): item for item in board_layers[1:] if isinstance(item, list)}
    if not present:
        in_use = used_layers(board, [name for name in BOTTOM_SIDE_LAYERS if name in current])
        if in_use:
            raise SettingsError("a single-sided board has no bottom mask, paste or silkscreen, "
                                f"these still have items: {', '.join(in_use)}")
        board_layers[1:] = [item for item in board_layers[1:]
                            if not (isinstance(item, list) and str(item[1]) in BOTTOM_SIDE_LAYERS)]
        return
    old_ids = int(str(current["B.Cu"][0])) == 31
    for name, (new_id, old_id, front) in BOTTOM_SIDE_LAYERS.items():
        if name in current:
            continue
        entry = [Symbol(str(old_id if old_ids else new_id)), name, Symbol("user")]
        if name in BOTTOM_SIDE_USER_NAMES:
            entry.append(BOTTOM_SIDE_USER_NAMES[name])
        after = board_layers.index(current[front]) if front in current else len(board_layers) - 1
        board_layers.insert(after + 1, entry)


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
        node = [Symbol("layer"), f"dielectric {dielectric_index}", [Symbol("type"), layer.type]]
        for i, part in enumerate((layer, *layer.sublayers)):
            # KiCad writes a dielectric's further materials after an addsublayer token
            node = colored(node + ([Symbol("addsublayer")] if i else []), part.color) + [
                [Symbol("thickness"), num(part.thickness)], [Symbol("material"), part.material],
                [Symbol("epsilon_r"), num(part.epsilon_r)],
                [Symbol("loss_tangent"), num(part.loss_tangent)]]
        nodes.append(node)
    if not stackup.single_sided:  # nothing on a single-sided board's bottom
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
        set_bottom_side_layers(board, present=not stackup.single_sided)
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


def check_vias_fit_rules(vias: Vias, rules: Rules) -> None:
    limits = rules.constraints
    for size in vias.sizes:
        if (size.diameter < limits.min_via_diameter - 1e-9
                or size.drill < limits.min_through_hole_diameter - 1e-9):
            raise SettingsError(f"via {size.diameter}/{size.drill} is under the {rules.name} "
                                f"minimum ({limits.min_via_diameter}/"
                                f"{limits.min_through_hole_diameter})")
        if (size.diameter - size.drill) / 2 < limits.min_via_annular_width - 1e-9:
            raise SettingsError(f"via {size.diameter}/{size.drill} has less annular ring "
                                f"than the {rules.name} minimum {limits.min_via_annular_width}")


def apply_to_project(project: dict, stackup: Stackup | None, rules: Rules | None,
                     vias: Vias | None, sizes: Sizes) -> None:
    design = project["board"]["design_settings"]
    default = next(c for c in project["net_settings"]["classes"] if c["name"] == "Default")
    if rules:
        design["rules"].update(vars(rules.constraints))
        default.update({k: v for k, v in vars(rules.default_netclass).items() if v is not None})
    if vias:
        if rules:
            check_vias_fit_rules(vias, rules)
        design["rules"]["allow_blind_buried_vias"] = vias.blind
        design["rules"]["allow_microvias"] = vias.microvia is not None
        # The leading 0/0 is KiCad's "use net class via" entry
        design["via_dimensions"] = [{"diameter": 0.0, "drill": 0.0},
                                    *(vars(size).copy() for size in vias.sizes)]
        default["via_diameter"], default["via_drill"] = vias.sizes[0].diameter, vias.sizes[0].drill
        if vias.microvia:
            design["rules"]["min_microvia_diameter"] = vias.microvia.diameter
            design["rules"]["min_microvia_drill"] = vias.microvia.drill
            default["microvia_diameter"] = vias.microvia.diameter
            default["microvia_drill"] = vias.microvia.drill
    if stackup:
        min_width = design["rules"].get("min_track_width", 0)
        # The leading 0 is KiCad's "use net class width" entry
        design["track_widths"] = [0.0, *predefined_track_widths(stackup, sizes, min_width)]


# --- Custom rules (.kicad_dru) -------------------------------------------------

DRU_BEGIN = "# fab_settings vias: begin (generated, edit the vias profile instead)"
DRU_END = "# fab_settings vias: end"
DRU_BLOCK = re.compile(rf"\n*{re.escape(DRU_BEGIN)}.*?{re.escape(DRU_END)}\n?", re.S)


def via_rules(vias: Vias, inner_count: int = 0) -> list[str]:
    rules = []
    if vias.blind and not vias.buried:
        rules.append('(rule "No buried vias"\n\t(constraint disallow buried_via))')
    if vias.blind and not vias.skip_vias:
        # KiCad micro vias only join adjacent layers, so any blind via is a skip via
        rules.append('(rule "No skip vias"\n\t(constraint disallow blind_via))')
    if vias.microvia and not vias.inner_microvias:
        # A micro via joins adjacent layers and a rule's (layer) scope matches a via
        # on either end, so a via touching In2..In(n-1) has both ends inner. Those
        # touching only In1 or In(n) run to the outer layers, as 1+N+1 needs.
        for index in range(2, inner_count):
            rules.append(f'(rule "No inner micro vias (In{index}.Cu)"\n'
                         f'\t(constraint disallow micro_via)\n\t(layer "In{index}.Cu"))')
    for net in vias.through_nets:
        for kind in ("micro_via", "blind_via", "buried_via"):
            rules.append(f'(rule "{net} through vias only ({kind})"\n'
                         f'\t(constraint disallow {kind})\n'
                         f"\t(condition \"A.NetName == '{net}'\"))")
    return rules


def apply_to_custom_rules(text: str, vias: Vias, inner_count: int = 0) -> str:
    """Replace this script's block in a .kicad_dru, leaving the user's own rules alone."""
    text = DRU_BLOCK.sub("", text)
    rules = via_rules(vias, inner_count)
    if rules:
        block = "\n".join([DRU_BEGIN, *rules, DRU_END]) + "\n"
        text = (text.rstrip("\n") + "\n\n" if text.strip() else "(version 1)\n\n") + block
    return text if text.strip() != "(version 1)" else ""


def project_path(board: Path) -> Path:
    return board.with_suffix(".kicad_pro")


def custom_rules_path(board: Path) -> Path:
    return board.with_suffix(".kicad_dru")


def apply(board: Path, output: Path, stackup: Stackup | None, colors: Colors | None,
          rules: Rules | None, vias: Vias | None = None) -> None:
    text = apply_to_board(board.read_text(encoding="utf-8"), stackup, colors, rules)
    project = None
    if stackup or rules or vias:
        if project_path(board).exists():
            project = json.loads(project_path(board).read_text(encoding="utf-8"))
            apply_to_project(project, stackup, rules, vias, load_sizes())
        elif rules or vias:
            raise SettingsError(f"rules and vias go in {project_path(board)}, "
                                "which doesn't exist")
    output.write_text(text, encoding="utf-8")
    if project is not None:
        project_path(output).write_text(json.dumps(project, indent=2) + "\n", encoding="utf-8")
    if vias:
        source = custom_rules_path(board)
        dru = apply_to_custom_rules(source.read_text(encoding="utf-8") if source.exists() else "",
                                    vias, len(set(re.findall(r'"In(\d+)\.Cu"', text))))
        target = custom_rules_path(output)
        if dru:
            target.write_text(dru, encoding="utf-8")
        else:
            target.unlink(missing_ok=True)


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
        vias = load_setting("vias", parts["vias"]) if parts.get("vias") else None
        directory = out_dir / name
        shutil.rmtree(directory, ignore_errors=True)
        directory.mkdir(parents=True)
        board = directory / f"{name}.kicad_pcb"
        pcbnew.SaveBoard(str(board), pcbnew.NewBoard(str(board)))
        # Local view settings, not part of what Import Settings reads
        board.with_suffix(".kicad_prl").unlink(missing_ok=True)
        apply(board, board, stackup, colors, rules, vias)
        print(f"fab_settings: {board}: "
              + ", ".join(x.name for x in (stackup, colors, rules, vias) if x))


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
    commands.add_parser("list", help="list available stackups, colours, rules and vias")
    apply_parser = commands.add_parser("apply", help="apply settings to a board")
    apply_parser.add_argument("board", type=Path, help=".kicad_pcb to edit in place")
    apply_parser.add_argument("-o", "--output", type=Path,
                              help="write here (and its .kicad_pro) instead of in place")
    for kind, flag in (("stackups", "--stackup"), ("colors", "--colors"), ("rules", "--rules"),
                       ("vias", "--vias")):
        apply_parser.add_argument(flag, dest=kind, help=f"name from fab-settings/{kind}/ "
                                  "or a path to a .yaml file")
    templates_parser = commands.add_parser("templates", help="write the boards in a template list")
    templates_parser.add_argument("list", type=Path,
                                  help="YAML of board name -> stackup, colors, rules, vias")
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
                parser.error("give at least one of --stackup, --colors, --rules, --vias")
            apply(args.board, args.output or args.board, chosen.get("stackups"),
                  chosen.get("colors"), chosen.get("rules"), chosen.get("vias"))
            print(f"fab_settings: {args.output or args.board}: "
                  + ", ".join(setting.name for setting in chosen.values()))
    except SettingsError as error:
        sys.exit(f"fab_settings: {error}")


if __name__ == "__main__":
    main()
