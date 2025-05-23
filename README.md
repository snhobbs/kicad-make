# kicad-make
Makefile to create releases of KiCAD designs. This project has a branch for each version of versions of KiCAD that have the CLI tool (v7, v8, & v9 currently).

## Setup
At a minimum you'll need the kicad-cli which is available with KiCAD 7+. Choose the correct release or branch for the version you're using.
Make sure kicad-cli is on your path or edit the makefile so KICAD-CLI is set correctly.

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

## Generated Files
+ PDF Schematic
+ SVG board outline (edge cuts)
+ Gerbers w/ drill file & zipped gerbers
+ Interactive HTML BOM
+ STEP model of board
+ centroid w/ KiCAD and JLCPCB format
+ Full BOM and JLCPCB version
+ PDF gerber report
+ GenCAD
+ ODB++
+ IPC2581
+ Renders of the board

## Notes
### Semantic Versioning
We encourage using semantic numbering for board versions. See the [blog post](https://www.maskset.net/blog/2023/02/26/semantic-versioning-for-hardware/) for the versioning scheme.
As rolling the patch number ({Major}.{Minor}.{Subversion}) is done to reflect BOM or manufacturing changes then the released board files will only be tied to the major & minor number. To reflect this we use {Major}.{Minor}.X as the board version. You can use any version number you want though.

If VERSION is not set then the abreviated git hash is used.

## Usage
You can copy or symlink the makefile into your project however I prefer to point to the file directly with makes -f command.
The only usage requirements are:

+ All dependencies need to be on your path
+ make is called from the project directory
+ make finds the Makefile

### Create a board version
This is the default target and generates everything.
```bash
make -f kicad-make/Makefile PROJECT=<name of kicad project> VERSION=<version number>
```

### Skip DRC Check
Try to not do this too often... Exports everything, skipping ERC and DRC check.

```bash
make -f kicad-make/Makefile PROJECT=<name of kicad project> VERSION=<version number> no-drc
```

### Export schematic
```bash
make -f kicad-make/Makefile PROJECT=<name of kicad project> VERSION=<version number> schematic
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


# FIXME
+ Add check of critical parts placement
