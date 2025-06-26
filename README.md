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

## Features (v9)
+ Runs DRC & ERC. If these do not pass than the manufacturing files won't be generated.
+ Includes both generic and JLCPCB targeted outputs

### Generated Files
+ PDF Schematic
+ SVG board outline (edge cuts)
+ Gerbers w/ drill file & zipped gerbers
+ Interactive HTML BOM
+ STEP model of board
+ centroid w/ KiCad and JLCPCB format
+ Full BOM and JLCPCB version
+ PDF gerber report
+ GenCAD
+ ODB++
+ IPC2581
+ Renders of the board

## Notes
### Semantic Versioning
We encourage using semantic numbering for board versions. See the [blog post](https://www.maskset.net/blog/2023/02/26/semantic-versioning-for-hardware/) for the versioning scheme.
As rolling the subversion number ({Major}.{Minor}.{Subversion}) is done to reflect BOM or manufacturing changes then the released board files will only be tied to the major & minor number. To reflect this we use {Major}.{Minor}.X as the board version. You can use any version number you want though.

## Usage

You can copy or symlink the makefile into your project however I prefer to point to the file directly with makes -f command.
The only usage requirements are:

+ All dependencies need to be on your path
+ make is called from the project directory
+ make finds the Makefile

### Create a board version
This is the default target and generates everything.
```bash
make -f kicad-make/Makefile PROJECT=<name of KiCad project> VERSION=<version number>
```

### Skip DRC Check
Try to not do this too often... Exports everything, skipping ERC and DRC check.

```bash
make -f kicad-make/Makefile PROJECT=<name of KiCad project> VERSION=<version number> no-drc
```

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
docker run -v $(pwd):/home/kicad -it --rm --name t
asd kicad-env make -f /usr/share/kicad-make/Makefile PROJECT=jlcpcb-4Layer-JLC04161H-2116D VER
SION=0.1.X DIR=kicad-setting-boards/jlcpcb-4Layer-JLC04161H-2116D no-drc
```
This uses the settings board as an example build and uses the makefile in the Docker image.


## High Level Targets

| **Target**      | **Description**                                           |
| --------------- | --------------------------------------------------------- |
| `all`           | Default target, triggers `release`.                       |
| `clean`         | Cleans up generated files and directories.                |
| `release`       | Full release process (DRC/ERC, manufacturing, packaging). |
| `documents`     | Generates schematic, BOM, step, IBOM, & gerberpdf         |
| `manufacturing` | Generates manufacturing files (Gerbers, IPC2581, etc.).   |
| `no-drc`        | Skips DRC & ERC, completes the rest of the release process |
| `schematic`     | Generates schematic PDF.                                  |
| `boms`          | Generates BOM files (normal and LCSC).                    |
| `gerbers`       | Generates Gerber files.                                   |
| `fabzip`        | Zips Gerber files and centroids for ordering.         |
| `testpoints`    | Generates a testpoint report.                             |
| `step`          | Generates STEP file of the board.                |
| `ibom`          | Generates interactive BOM HTML.                           |
| `gerberpdf`     | Converts a PDF report with the critical gerber layers     |
| `centroid`      | Generates centroid files for assembly.                    |
| `drc`           | Runs Design Rule Check and saves the report.              |
| `erc`           | Runs Electrical Rule Check and saves the report.          |
| `ipc2581`       | Generates IPC2581 files.                                  |
| `board`         | Builds final board (Gerbers, drills, centroid, outline).  |
| `renders`       | Generates 3D renders of the PCB (top, bottom, front, back, left, right). |
| `gencad`        | Generates GEN-CAD files.                                                 |
| `odb`           | Generates ODB++ files.                                                   |


# FIXME
+ Add check of critical parts placement
