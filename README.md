# kicad-make

Makefile for building a board revision. I've used the generated files with JLCPCB, Screaming Circuits, and OSHPark.

## Features
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

## Notes
### Semantic Versioning
We encourage using semantic numbering for board revisions. See the blog post <https://www.maskset.net/blog/2023/02/26/semantic-versioning-for-hardware/> for the versioning scheme.
As rolling the patch number ({Major}.{Minor}.{Patch}) is done to reflect BOM or manufacturing changes then the released board files will only be tied to the major & minor number. To reflect this we use {Major}.{Minor}.X as the board revision. You can use any version number you want though.

### IBOM Version Number
The IBOM script uses the version number in the PCB title block in the filename. Note that this
may be different than the declared version. We left this as your version should be the same and
this acts as an easy indication you have a version issue.

## Usage

### Create a board revision
This is the default target and generates everything.
```bash
make -f kicad-make/Makefile PROJECT=<name of kicad project> REVISION=<revision number>
```

### Skip DRC Check
Try to not do this too often... Exports everything, skipping ERC and DRC check.

```bash
make -f kicad-make/Makefile PROJECT=<name of kicad project> REVISION=<revision number> no-drc
```

### Export schematic
```bash
make -f kicad-make/Makefile PROJECT=<name of kicad project> REVISION=<revision number> schematic
```


## Example Usage
```bash
>> ls
project.kicad_pro   project.kicad_sch   project.kicad_pcb   project.kicad_prl

>> make -f kicad-make/Makefile PROJECT=project REVISION=0.1.X

>> ls
project.kicad_pro   project.kicad_sch   project.kicad_pcb                   project.kicad_prl
project_0.1.X.zip   project_0.1.X.pdf   project_0.1.X_interactive_bom.html  fab
mechanical
```
