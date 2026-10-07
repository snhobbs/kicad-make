# kicad-make

Makefile to create releases of KiCad designs. This project has a branch for each version of versions of KiCad that have the CLI tool (v7, v8, & v9 currently).

## Structure

There is one common Makefile and several manufacture specific targets.
Additional manufacturer targets can be added as separate files and included at the bottom of Makefile.
To make all targets including the jlcpcb and macrofab manufacturing files use:

```sh
make -f kicad-make/Makefile PROJECT=<name of KiCad project> VERSION=<version number> manufacturing_release -j$(nproc)
```

## Setup

At a minimum you'll need the kicad-cli which is available with KiCad 7+ some of the features here are only available
in v8+. Depending on how you installed KiCad this could be a whole bunch of places. Find it and add the location
to your path.

A Dockerfile is included to make setup easier.
A description of how to use it and why is described [here](https://www.maskset.net/blog/2025/06/30/using-kicad-with-docker-to-manage-and-upgrade-release-versions/)

```bash
docker build -f Dockerfile --build-arg UID=$(id -u) \
--build-arg GID=$(id -g) --build-arg USERNAME=$(whoami) -t kicad9 .
```

### kicad-cli for different installation types

**flatpak**

```bash
KICADCLI=flatpak run --command=kicad-cli org.kicad.KiCad
```

**snap**

```bash
KICADCLI=/snap/bin/kicad.kicad-cli
```

**docker**

```bash
KICADCLI=docker run -v /tmp/.X11-unix:/tmp/.X11-unix -v ${HOME}:${HOME} -it --rm -e DISPLAY=:0 --name kicad-cli kicad/kicad:9.0 kicad-cli
```

### Secondary Tools

For python tools you'll also need to set the PYTHONPATH to find the pcbnew.py library.
For Ubuntu when using aptitude it should show up in /usr/lib/python3/dist-packages.
I add the following to my .zshrc / .bashrc.

```sh
PCBNEW_DIR=/usr/lib/python3/dist-packages
export PYTHONPATH=${PYTHONPATH}:${PCBNEW_DIR}
```

Install the subdirectories in the same python environment. If these outputs are not
needed then remove the related lines.

```sh
git submodule update --init --recursive
cd libs/InteractiveHtmlBom/ && pip install .
```

Fab settings (`scripts/fab_settings.py`) need `sexpdata` and `pyyaml`: `pip install sexpdata pyyaml`.

## Features (v9)

- Runs DRC & ERC. If these do not pass than the manufacturing files won't be generated.
- Includes both generic and JLCPCB targeted outputs

### Generated Files

- PDF Schematic
- SVG board outline (edge cuts)
- Gerbers w/ drill file & zipped gerbers
- Interactive HTML BOM
- STEP model of board
- centroid w/ KiCad and JLCPCB format
- Full BOM and JLCPCB version
- PDF gerber report
- GenCAD
- ODB++
- IPC2581
- Renders of the board

## Notes

### Semantic Versioning

We encourage using semantic numbering for board versions. See the [blog post](https://www.maskset.net/blog/2023/02/26/semantic-versioning-for-hardware/) for the versioning scheme.
As rolling the subversion number ({Major}.{Minor}.{Subversion}) is done to reflect BOM or manufacturing changes then the released board files will only be tied to the major & minor number. To reflect this we use {Major}.{Minor}.X as the board version. You can use any version number you want though.

## Usage

You can copy or symlink the makefile into your project however I prefer to point to the file directly with makes -f command.
The only usage requirements are:

- All dependencies need to be on your path
- make is called from the project directory
- make finds the Makefile

### Create a board version

This is the default target and generates everything.

```bash
make -f kicad-make/Makefile PROJECT=<name of KiCad project> VERSION=<version number>
```

### Drawing sheet

To use a custom style sheet, pass a `.kicad_wks` file:

```bash
make -f kicad-make/Makefile PROJECT=<name> VERSION=<version> SCH_DRAWING_SHEET=path/to/sheet.kicad_wks
```

`PCB_DRAWING_SHEET` follows `SCH_DRAWING_SHEET` and can be set separately. Set `SCH_DRAWING_SHEET=` (empty) to use the sheet from the project's Schematic Setup and Board Setup. A sheet you pass that doesn't exist stops the build. If the default sheet is missing, for example in a container without it mounted, make warns and uses the project's sheet.

### Skip DRC Check

Try to not do this too often... Exports everything, skipping ERC and DRC check.

```bash
make -f kicad-make/Makefile PROJECT=<name of KiCad project> VERSION=<version number> no-drc
```

### Boards without a schematic

Generated boards and panels have no `.kicad_sch`. `pcb-release` skips ERC, the schematic PDF, BOMs and the schematic parity check, and refills zones before DRC:

```bash
make -f kicad-make/Makefile PROJECT=<name of KiCad project> VERSION=<version number> pcb-release
```

It runs `pcb-drc`, `pcb-manufacturing` (gerbers, drill, outline, IPC2581, ODB++, GenCAD), `pcb-fabzip` (`<project>_<version>_pcb_manufacturing.zip`) and `pcb-documents` (gerber PDF, STEP, renders). Each can also be run on its own.

### Export schematic

```bash
make -f kicad-make/Makefile PROJECT=<name of KiCad project> VERSION=<version number> schematic
```

## Example Usage

```bash
>> ls
project.kicad_pro   project.kicad_sch   project.kicad_pcb   project.kicad_prl

>> make -f kicad-make/Makefile PROJECT=project VERSION=0.1.X

>> ls
project.kicad_pro   project.kicad_sch   project.kicad_pcb                   project.kicad_prl
project_0.1.X.zip   project_0.1.X.pdf   project_0.1.X_interactive_bom.html  fab
mechanical
```

## Docker Example

A Dockerfile example is included to help with setting up your environment.
I prefer to setup the environment locally and would instead recommend setting the tool paths in the Makefile
itself to use the Docker commands. The `kicad-cli` command has a few examples of how to do that in the Makefile.

### Build the image

From the kicad-make repo directory run:

```bash
docker build -t kicad-env .
```

### Build a project

From the kicad-make repo directory run:

```bash
docker run -v $(pwd):/home/kicad -it --rm --name kicad-make kicad-env \
    make -f /usr/share/kicad-make/Makefile PROJECT=<project> VERSION=0.1.X DIR=<project dir> no-drc
```

This uses the makefile in the Docker image.

## High Level Targets

| **Target**      | **Description**                                                                               |
| --------------- | --------------------------------------------------------------------------------------------- |
| `all`           | Default target, triggers `release`.                                                           |
| `clean`         | Cleans up generated files and directories.                                                    |
| `release`       | Full release process (DRC/ERC, manufacturing, packaging).                                     |
| `documents`     | Generates schematic, BOM, step, IBOM, & gerberpdf                                             |
| `manufacturing` | Generates manufacturing files (Gerbers, IPC2581, etc.).                                       |
| `no-drc`        | Skips DRC & ERC, completes the rest of the release process                                    |
| `pcb-release`   | Release for a board with no schematic: DRC (no parity, zones refilled), manufacturing, zip, documents. |
| `schematic`     | Generates schematic PDF.                                                                      |
| `boms`          | Generates BOM files (normal and LCSC).                                                        |
| `gerbers`       | Generates Gerber files.                                                                       |
| `fabzip`        | Zips Gerber files and centroids for ordering.                                                 |
| `testpoints`    | Generates a testpoint report.                                                                 |
| `step`          | Generates STEP file of the board.                                                             |
| `models`        | VRML + STEP of the board for use as a footprint 3D model on another board.                    |
| `ibom`          | Generates interactive BOM HTML.                                                               |
| `gerberpdf`     | Converts a PDF report with the critical gerber layers                                         |
| `centroid`      | Generates centroid files for assembly.                                                        |
| `drc`           | Runs Design Rule Check and saves the report.                                                  |
| `erc`           | Runs Electrical Rule Check and saves the report.                                              |
| `ipc2581`       | Generates IPC2581 files.                                                                      |
| `board`         | Builds final board (Gerbers, drills, centroid, outline).                                      |
| `renders`       | Generates 3D renders of the PCB (top, bottom, front, back, left, right, angled top & bottom). |
| `gencad`        | Generates GEN-CAD files.                                                                      |
| `odb`           | Generates ODB++ files.                                                                        |

## Fab settings

`fab-settings/` holds three independent sets of YAML files, so any stackup can
be combined with any colours and rules (keep to combinations your fab offers):

| Directory | What | Written to |
| --- | --- | --- |
| `stackups/` | Copper and dielectric thicknesses, materials, dielectric constants, mask thickness, board body colour, optional fab impedance widths | `.kicad_pcb` stackup, layer table, board thickness |
| `colors/` | Solder mask and silkscreen colours, copper finish | `.kicad_pcb` stackup |
| `rules/` | Fab minimums (Constraints), Default net class, solder mask expansion and minimum web | `.kicad_pro`, `.kicad_pcb` |

`sizes.yaml` lists the predefined track widths written with every stackup:
6, 8 and 10 mil, 0.5, 1 and 2 mm, plus the 50 and 100 ohm top layer widths.
Those are solved as uncoated surface microstrip over the top dielectric unless
the stackup gives `impedance_widths` from the fab's calculator; widths under
the rules' minimum track width are left out with a warning.

Stackup and colours drive the 3D viewer, `kicad-cli` renders
(`--use-board-stackup-colors`), and the STEP and VRML exports, so set them on
the board for the models to come out right.

### Applying to a board

`scripts/fab_settings.py` edits the board (and its project for rules) in
place. Inner copper layers are added or removed to match a stackup; it refuses
to remove one that still has items on it. Only the edited settings change, so
the board diffs cleanly. Close the board in KiCad first, or KiCad will
overwrite it on save.

```bash
scripts/fab_settings.py list
scripts/fab_settings.py apply project.kicad_pcb --stackup jlcpcb-4l-fr4-1.6mm --colors green --rules jlcpcb-4l
scripts/fab_settings.py apply project.kicad_pcb --colors black
```

Names can also be paths to your own `.yaml` files.

### Template boards for Import Settings

`kicad-setting-boards/` has a board for each entry in its `templates.yaml`
(stackup + colours + rules). In KiCad use Board Setup > Import Settings and
pick one, ticking the stackup, constraints, net classes, predefined sizes and
solder mask options. The boards are committed; after changing `fab-settings/`
or `templates.yaml` regenerate them with their own Makefile and commit the
result:

```bash
make -C kicad-setting-boards
```

### Notes on the data

- Flex coverlay is modelled as the solder mask, which is where KiCad renders it.
- Aluminum core (`jlcpcb-1l-aluminum-*`, rules `jlcpcb-aluminum`, colours
  `white-hasl` or `black-hasl`) is one copper layer on an insulation layer on
  the aluminium base. KiCad has no 1-layer board, so the stackup is
  `single_sided`: B.Cu stays in the board with no thickness, and nothing goes
  on it, and the board has no bottom mask, paste or silkscreen layers (the
  bottom is the bare metal). Applying it refuses a board with items on those. The base is a `sublayers` entry of the dielectric, so the 50 ohm
  width is solved over the insulation alone. JLCPCB doesn't publish the
  insulation's thickness or dielectric constant; the 0.1 mm and 4.5 are
  typical values and say so. There are no plated holes, so no vias.
- JLCPCB doesn't publish layer-by-layer builds for 4-layer flex or the 0.8 and
  1.0 mm 4-layer FR4; those stackups are derived and say so.
- Rules use the fab's no-surcharge limits; values a fab doesn't publish are
  KiCad defaults and are commented.
- Needs `sexpdata` and `pyyaml`; the templates also need KiCad's `pcbnew`
  Python module.

## Renders

Renders, the STEP and the VRML models use the board's own stackup colours:
set them with `scripts/fab_settings.py apply --colors` or by importing a
template board (see [Fab settings](#fab-settings)).

Renders include angled top and bottom views (`Render_ANGLED_TOP.png`,
`Render_ANGLED_BOTTOM.png`), tilted by `RENDER_ANGLE` (default `-45,0,45`)
with `RENDER_ANGLED_ZOOM` (default `0.85`).

Lighting is set with `RENDER_LIGHT_CAMERA`, `RENDER_LIGHT_TOP`,
`RENDER_LIGHT_BOTTOM`, `RENDER_LIGHT_SIDE` and `RENDER_LIGHT_SIDE_ELEVATION`.
The straight-down top and bottom views are lit from the sides only, since a
head-on light puts a milky sheen over the whole solder mask; set those with
`RENDER_FLAT_LIGHT_CAMERA`, `RENDER_FLAT_LIGHT_TOP`, `RENDER_FLAT_LIGHT_BOTTOM`
and `RENDER_FLAT_LIGHT_SIDE`.

`kicad-cli` takes the part material mode from your 3D viewer settings, and
"CAD colors" gives flat, washed out grey parts. Renders print a warning if
the mode isn't Realistic; change it in the 3D viewer preferences (Material
properties).

# FIXME

- Add check of critical parts placement
