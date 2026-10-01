#===============================================================
# Project Information - Ensure variables PROJECT & VERSION are set
#===============================================================
ifndef PROJECT
$(error PROJECT is not set)
endif

# Use VERSION="$(shell cd $(DIR) && git show --pretty='%h' | head --lines=1)" for the git commit
ifndef VERSION
$(error VERSION is not set)
endif

NOCHECKS?=0

ifeq ($(NOCHECKS),1)
$(warning Ignoring ERC & DRC output, manual error checking required)
endif

TIME := $(shell date +%s)

ROOT_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))

DIR ?= $(shell pwd)
_DIR := $(abspath $(DIR))

OUTDIR ?= $(_DIR)
_OUTDIR = $(abspath $(OUTDIR))
#===============================================================
# Directory Paths & Tool Paths
#===============================================================
SCH = $(abspath $(_DIR)/$(PROJECT).kicad_sch)
$(info $(SCH))
PCB = $(_DIR)/$(PROJECT).kicad_pcb
PCBBASE=$(basename $(notdir $(PCB)))
SCHBASE=$(basename $(notdir $(SCH)))

MANUFACTURING_DIR = $(_OUTDIR)/fab
ASSEMBLY_DIR = $(MANUFACTURING_DIR)/assembly
GERBER_DIR = $(MANUFACTURING_DIR)/gerbers
LOGS_DIR = $(_OUTDIR)/logs
MECH_DIR = $(_OUTDIR)/mechanical

# Tool paths
KICADCLI=kicad-cli
IBOM_SCRIPT=generate_interactive_bom
KICAD_TESTPOINTS_SCRIPT=kicad_testpoints

# Drawing Sheet Paths
DEFAULT_DRAWING_SHEET = 
SCH_DRAWING_SHEET ?= $(DEFAULT_DRAWING_SHEET)
PCB_DRAWING_SHEET ?= $(SCH_DRAWING_SHEET)

# A sheet passed in that doesn't exist is an error. The default sheet missing
# (another machine, a container without the mount) falls back to the project's
# sheet with a warning.
define check_drawing_sheet
ifneq ($$($(1)),)
ifeq ($$(wildcard $$($(1))),)
ifeq ($$(origin $(1)),file)
$$(warning $(1) not found, using the project drawing sheet: $$($(1)))
$(1) :=
else
$$(error $(1) not found: $$($(1)))
endif
endif
endif
endef
$(eval $(call check_drawing_sheet,SCH_DRAWING_SHEET))
$(eval $(call check_drawing_sheet,PCB_DRAWING_SHEET))

SCH_DRAWING_SHEET_FLAG = $(if $(SCH_DRAWING_SHEET),--drawing-sheet "$(SCH_DRAWING_SHEET)")
PCB_DRAWING_SHEET_FLAG = $(if $(PCB_DRAWING_SHEET),--drawing-sheet "$(PCB_DRAWING_SHEET)")

#===============================================================
# Generated File Paths
#===============================================================
BOM=$(ASSEMBLY_DIR)/$(SCHBASE)_$(VERSION)_BOM.csv
UNCLUSTERED_BOM=$(ASSEMBLY_DIR)/$(SCHBASE)_$(VERSION)_UnclusteredBOM.csv
ERC=$(LOGS_DIR)/erc.rpt
DRC=$(LOGS_DIR)/drc.rpt

# Visualizations
PDFSCH=$(_OUTDIR)/$(SCHBASE)_$(VERSION)_schematic.pdf
IBOM=$(_OUTDIR)/$(PCBBASE)_$(VERSION)_interactive_bom.html
GERBER_PDF_DIR=${_OUTDIR}/gerberpdf
GERBERPDF=${_OUTDIR}/${PCBBASE}_${VERSION}_gerbers.pdf
RENDER_DIR=${_OUTDIR}/renders
RENDERS:= ${RENDER_DIR}/Render_TOP.png \
		   ${RENDER_DIR}/Render_BOTTOM.png \
		   ${RENDER_DIR}/Render_LEFT.png \
		   ${RENDER_DIR}/Render_RIGHT.png \
		   ${RENDER_DIR}/Render_FRONT.png \
		   ${RENDER_DIR}/Render_BACK.png \
		   ${RENDER_DIR}/Render_ANGLED_TOP.png \
		   ${RENDER_DIR}/Render_ANGLED_BOTTOM.png

# Angled renders: perspective view tilted by RENDER_ANGLE ("X,Y,Z" degrees)
# from the top or bottom view; lower RENDER_ANGLED_ZOOM if the board is cropped.
RENDER_ANGLE ?= -45,0,45
RENDER_ANGLED_ZOOM ?= 0.85

# Studio lighting: angled side lights do most of the work because light that
# hits the glossy solder mask head-on (camera, and top/bottom in top/bottom
# views) reflects straight into the camera and washes the colour out. A high
# elevation keeps their shadows short; the dim camera light fills them in.
# Intensities are 0-1 (or "R,G,B"), elevation is in degrees above the board.
RENDER_LIGHT_CAMERA ?= 0.25
RENDER_LIGHT_TOP ?= 0.1
RENDER_LIGHT_BOTTOM ?= 0.1
RENDER_LIGHT_SIDE ?= 0.25
RENDER_LIGHT_SIDE_ELEVATION ?= 70
RENDER_LIGHTS ?= --light-camera ${RENDER_LIGHT_CAMERA} \
		--light-top ${RENDER_LIGHT_TOP} \
		--light-bottom ${RENDER_LIGHT_BOTTOM} \
		--light-side ${RENDER_LIGHT_SIDE} \
		--light-side-elevation ${RENDER_LIGHT_SIDE_ELEVATION}
RENDER_OPTS ?= --background transparent --use-board-stackup-colors \
		--quality high ${RENDER_LIGHTS}

# Straight-down top/bottom views: the board is flat and faces the camera, so
# any head-on light puts the same highlight on every point of the mask and
# the whole board goes milky. Light these from the sides only.
RENDER_FLAT_LIGHT_CAMERA ?= 0
RENDER_FLAT_LIGHT_TOP ?= 0
RENDER_FLAT_LIGHT_BOTTOM ?= 0
RENDER_FLAT_LIGHT_SIDE ?= 0.32
RENDER_FLAT = $(foreach side,TOP BOTTOM,${RENDER_DIR}/Render_$(side).png \
		${_OUTDIR}/${PCBBASE}_${VERSION}_Render_$(side).png)
$(RENDER_FLAT): RENDER_LIGHT_CAMERA = ${RENDER_FLAT_LIGHT_CAMERA}
$(RENDER_FLAT): RENDER_LIGHT_TOP = ${RENDER_FLAT_LIGHT_TOP}
$(RENDER_FLAT): RENDER_LIGHT_BOTTOM = ${RENDER_FLAT_LIGHT_BOTTOM}
$(RENDER_FLAT): RENDER_LIGHT_SIDE = ${RENDER_FLAT_LIGHT_SIDE}

# kicad-cli takes the material mode from the 3D viewer settings, and "CAD
# colors" renders parts flat grey. render-check warns if it isn't Realistic.
KICAD_VERSION = $(shell $(KICADCLI) version 2>/dev/null | cut -d. -f1-2)
KICAD_USER_CONFIG = $(or $(KICAD_CONFIG_HOME),$(or $(XDG_CONFIG_HOME),$(HOME)/.config)/kicad)
VIEWER_3D_CONFIG = $(KICAD_USER_CONFIG)/$(KICAD_VERSION)/3d_viewer.json

# BOMS & Assembly
CENTROID_CSV=$(ASSEMBLY_DIR)/centroid.csv
CENTROID_GERBER=$(ASSEMBLY_DIR)/centroid.gerber

# Manufacturing Files
DRILL=$(MANUFACTURING_DIR)/gerbers/drill.drl
FABZIP=$(_OUTDIR)/$(PCBBASE)_$(VERSION)_manufacturing.zip
GENCAD=$(_OUTDIR)/GENCAD_$(PCBBASE)_$(VERSION).cad
ODB=$(_OUTDIR)/ODB_$(PCBBASE)_$(VERSION).zip
IPC2581=$(MANUFACTURING_DIR)/IPC2581_$(PCBBASE)_$(VERSION).xml
TESTPOINT_REPORT=$(_OUTDIR)/testpoints_$(PCBBASE)_$(VERSION).csv
NETLIST=$(_OUTDIR)/netlist_$(PCBBASE)_$(VERSION).csv

# MECHANICAL
STEP=$(MECH_DIR)/$(PCBBASE)_$(VERSION).step

# 3D models for placing this board on another (e.g. a daughter board on its
# motherboard). The VRML carries the board stackup's mask, silkscreen and
# finish colours for KiCad renders; the STEP of the same name replaces it in
# the motherboard's STEP export (--subst-models). Both share MODEL_ORIGIN ("XxYmm", board
# coordinates), which defaults to this board's grid origin: put the grid
# origin where the motherboard footprint's anchor is.
MODEL_ORIGIN ?= $(shell sed -n 's/.*(grid_origin \([-0-9.]*\) \([-0-9.]*\)).*/\1x\2mm/p' "$(PCB)" 2>/dev/null | head -n 1)
MODEL_BASE=$(MECH_DIR)/$(PCBBASE)_$(VERSION)_model
STEP_MODEL=$(MODEL_BASE).step
VRML_MODEL=$(MODEL_BASE).wrl
STEP_MODEL_FLAGS ?= --include-soldermask --include-silkscreen --include-pads \
		--no-dnp --subst-models
# KiCad footprint VRML models are in tenths of an inch
VRML_MODEL_FLAGS ?= --units tenths --no-dnp

OUTLINE=$(MECH_DIR)/board-outline.svg

COMMA:= ,
SPACE:= $(empty) $(empty)

BOMFIELDS="Reference,Value,Footprint,\$$(QUANTITY),\$$(DNP),Manufacturers Part Number,MPN,Notes"

# GerberPDF
PDF_GERBER_LAYERS:= \
	User.Drawings \
	User.Comments \
	Edge.Cuts \
	F.Silkscreen \
	F.Fab \
	F.Mask \
	F.Cu \
	In1.Cu \
	In2.Cu \
	In3.Cu \
	In4.Cu \
	In5.Cu \
	In6.Cu \
	In7.Cu \
	In8.Cu \
	In9.Cu \
	In10.Cu \
	In11.Cu \
	In12.Cu \
	In13.Cu \
	B.Cu \
	B.Mask \
	B.Fab \
	B.Silkscreen \
	PressurePins \
	Clearance \
	Support \
	Relief \
	Base \
	Outline

PDF_GERBER_LAYERS_CSV:= $(subst $(SPACE),$(COMMA),$(PDF_GERBER_LAYERS))
PDF_GERBER_FILES:= $(foreach f,${PDF_GERBER_LAYERS},${GERBER_PDF_DIR}/${PCBBASE}-$(subst .,_,$(f)).pdf)
	
DRC_FLAGS=--format=report --all-track-errors# --severity-all
ERC_FLAGS=--format=report# --severity-all

ifeq ($(NOCHECKS),0)
DRC_FLAGS += --exit-code-violations --schematic-parity
ERC_FLAGS += --exit-code-violations
endif

.PHONY: all clean
all: release


#===============================================================
# Create Directories if Not Exist
#===============================================================
$(LOGS_DIR) $(MANUFACTURING_DIR) $(ASSEMBLY_DIR) $(GERBER_DIR) $(MECH_DIR) $(OUTDIR) $(GERBER_PDF_DIR) $(RENDER_DIR):
	mkdir -p $@

#===============================================================
# Clean Up Generated Files
#===============================================================
clean:
	-rm ${GERBERPDF}
	-rm ${PDFSCH}
	-rm ${BOM}
	-rm ${STEP}
	-rm ${STEP_MODEL} ${VRML_MODEL}
	-rm ${CENTROID_GERBER}
	-rm ${CENTROID_CSV}
	-rm ${IBOM}
	-rm ${GERBER_DIR}/*.gbr
	-rm ${FABZIP}
	-rm ${OUTLINE}
	-rm ${LOGS_DIR}/*.log
	-rm ${LOGS_DIR}/*.rpt
	-rm ${IPC2581}
	-rm ${TESTPOINT_REPORT}
	-rm ${RENDERS}
	-rm ${GERBER_PDF_DIR}/*.pdf
	-rm ${GENCAD}
	-rm ${ODB}
	-rm -r ${GERBER_DIR}
	-rmdir ${MECH_DIR}
	-rmdir ${GERBER_DIR} ${ASSEMBLY_DIR} ${MANUFACTURING_DIR} ${GERBER_PDF_DIR} ${LOGS_DIR}


$(TESTPOINT_REPORT): $(PCB) | $(_OUTDIR)
	$(KICAD_TESTPOINTS_SCRIPT) by-fab-setting --pcb "$<" --out "$@"

# Move the log file to the final location if the command succeeds so it doesn't rerun
$(DRC): $(PCB) $(ERC) | $(LOGS_DIR)
	$(KICADCLI) pcb drc $(DRC_FLAGS) "$<" -o $(LOGS_DIR)/drc-out.log || { cat "$(LOGS_DIR)/drc-out.log"; exit 1; }
	mv $(LOGS_DIR)/drc-out.log "$@"

$(ERC): $(SCH) | $(LOGS_DIR)
	$(KICADCLI) sch erc $(ERC_FLAGS) "$<" -o $(LOGS_DIR)/erc-out.log || { cat  "$(LOGS_DIR)/erc-out.log"; exit 1; }
	mv $(LOGS_DIR)/erc-out.log "$@"

# Generates schematic
$(PDFSCH) : $(SCH) | $(_OUTDIR)
	$(KICADCLI) sch export pdf --black-and-white $(SCH_DRAWING_SHEET_FLAG) "$<" -o "$@"

$(BOM): $(SCH) | $(ASSEMBLY_DIR)
	$(KICADCLI) sch export bom "$<" --fields $(BOMFIELDS) --group-by="\$$(DNP),Value,Footprint,Manufacturers Part Number" --ref-range-delimiter="" -o "$@"

$(UNCLUSTERED_BOM): $(SCH) | $(ASSEMBLY_DIR)
	$(KICADCLI) sch export bom "$<" --fields $(BOMFIELDS) --ref-range-delimiter="" -o "$@"

# Complains about output needing to be a directory, work around this
$(DRILL): $(PCB) | $(GERBER_DIR)
	$(KICADCLI) pcb export drill --drill-origin plot --excellon-units mm "$<" -o $(GERBER_DIR)
	mv $(GERBER_DIR)/$(PCBBASE).drl "$@"

$(CENTROID_CSV): $(PCB) | $(ASSEMBLY_DIR)
	$(KICADCLI) pcb export pos --use-drill-file-origin --side both --format csv --units mm "$<" -o "$@"

$(STEP): $(PCB) | $(MECH_DIR)
	$(KICADCLI) pcb export step "$<" --drill-origin --subst-models -f -o "$@"

check-model-origin:
ifeq ($(strip $(MODEL_ORIGIN)),)
	$(error No grid origin on $(PCB): set one where the motherboard footprint's anchor is, or pass MODEL_ORIGIN=XxYmm)
endif

$(STEP_MODEL): $(PCB) | check-model-origin $(MECH_DIR)
	$(KICADCLI) pcb export step "$<" --user-origin "$(MODEL_ORIGIN)" $(STEP_MODEL_FLAGS) -f -o "$@"

$(VRML_MODEL): $(PCB) | check-model-origin $(MECH_DIR)
	$(KICADCLI) pcb export vrml "$<" --user-origin "$(MODEL_ORIGIN)" $(VRML_MODEL_FLAGS) -f -o "$@"

# Screen size required for running headless
# https://github.com/openscopeproject/InteractiveHtmlBom/wiki/Tips-and-Tricks
$(IBOM): $(PCB) | $(ASSEMBLY_DIR)
	xvfb-run --auto-servernum --server-args "-screen 0 1024x768x24" $(IBOM_SCRIPT) "$<" \
		--dnp-field DNP --group-fields "Value,Footprint" --blacklist "X1,MH*" \
		--include-nets --normalize-field-case --no-browser --dest-dir ./ \
		--name-format "$(basename $@ )"

$(FABZIP): $(MANUFACTURING_DIR) $(CENTROID_CSV) gerbers $(IPC2581) boms
	zip -rj "$@" "$<"

$(OUTLINE): $(PCB) | $(MECH_DIR)
	$(KICADCLI) pcb export svg -l "Edge.Cuts" --black-and-white --exclude-drawing-sheet "$<" -o "$@"
${RENDER_DIR}/Render_%.png: ${PCB} | ${_OUTDIR} ${RENDER_DIR} render-check
	${KICADCLI} pcb render --side $(shell echo $* | tr A-Z a-z) ${RENDER_OPTS} "$<" -o "$@"

# Shorter stem than Render_%.png, so make prefers this rule for angled renders
${RENDER_DIR}/Render_ANGLED_%.png: ${PCB} | ${_OUTDIR} ${RENDER_DIR} render-check
	${KICADCLI} pcb render --side $(shell echo $* | tr A-Z a-z) ${RENDER_OPTS} \
		--perspective --rotate "${RENDER_ANGLE}" --zoom ${RENDER_ANGLED_ZOOM} "$<" -o "$@"

# Material mode 0 is Realistic, 1 Solid colors, 2 CAD colors
.PHONY: render-check
render-check:
	@mode=$$(grep -o '"material_mode": *[0-9]*' "$(VIEWER_3D_CONFIG)" 2>/dev/null | grep -o '[0-9]*$$'); \
	if [ -n "$$mode" ] && [ "$$mode" != 0 ]; then \
		echo "WARNING: 3D viewer material mode is $$mode, not Realistic (0), in $(VIEWER_3D_CONFIG)." >&2; \
		echo "WARNING: Renders will have flat or grey parts. Set Material properties to Realistic in the KiCad 3D viewer preferences." >&2; \
	fi

${IPC2581}: ${PCB} | ${_OUTDIR}
	${KICADCLI} pcb export ipc2581 "$<" -o "$@"

${GERBERPDF}: ${PCB} | ${GERBER_PDF_DIR}
	${KICADCLI} pcb export pdf ${PCB} --black-and-white \
		--cl "Edge.Cuts" \
		-l ${PDF_GERBER_LAYERS_CSV} \
		-o ${GERBER_PDF_DIR} \
		$(PCB_DRAWING_SHEET_FLAG) \
		--mode-separate \
		--include-border-title \
		--sketch-pads-on-fab-layers

# Filter out the layers that don't exist
# pdfunite $(shell for f in $(PDF_GERBER_FILES); do [ -e "$$f" ] && printf "%s " "$$f"; done) "$@"
	@existing_files=$$(for f in $(PDF_GERBER_FILES); do \
		[ -e "$$f" ] && printf "%s " "$$f"; done);\
		if [ -n "$$existing_files" ]; then \
			pdfunite  $$existing_files "$@"; \
			else \
			echo "No PDFS to merge"; \
			touch "$@"; \
	  fi

${_OUTDIR}/${PCBBASE}_${VERSION}_Render_%.png: ${PCB} | ${_OUTDIR} render-check
	${KICADCLI} pcb render \
		--side $(shell echo $* | tr A-Z a-z) \
		${RENDER_OPTS} "$<" -o "$@"

${GENCAD}: ${PCB} | ${_OUTDIR}
	${KICADCLI} pcb export gencad "$<" -o "$@"

${ODB}: ${PCB} | ${_OUTDIR}
	${KICADCLI} pcb export odb "$<" -o "$@"

gerbers: ${PCB} | ${GERBER_DIR}
	${KICADCLI} pcb export gerbers --use-drill-file-origin "$<" -o ${GERBER_DIR}

#===============================================================
# Compund Targets
#===============================================================

.PHONY: release gerbers odb gencad ipc2581 fabzip drc erc step step-model vrml models check-model-origin ibom schematic boms board gerberpdf centroid erc drc testpoints manufacturing no-drc documents

release: erc drc manufacturing fabzip documents

documents: schematic boms gerberpdf ibom step renders

manufacturing: ${GERBER_DIR} ${MECH_DIR} ${ASSEMBLY_DIR} gerbers board ipc2581 odb gencad testpoints
	echo "\n\n Manufacturing Files Exported \n\n"

no-drc: documents manufacturing fabzip

centroid: $(CENTROID_CSV)

boms: $(ASSEMBLY_DIR) $(BOM) $(UNCLUSTERED_BOM)

board: gerbers $(DRILL) $(CENTROID_CSV) boms $(OUTLINE)

#===============================================================
# Aliased Targets
#===============================================================

ipc2581: $(IPC2581)

odb: ${ODB}

gencad: ${GENCAD}
drc: $(DRC)

erc: $(ERC)

drc: $(DRC)

erc: $(ERC)

fabzip: $(FABZIP)

step: $(STEP)

step-model: $(STEP_MODEL)

vrml: $(VRML_MODEL)

models: step-model vrml

ibom: $(IBOM)

schematic: $(PDFSCH)

gerberpdf: ${GERBERPDF}

testpoints: $(TESTPOINT_REPORT)

renders: ${RENDERS}

#===============================================================
# Manufacturer Targets
#===============================================================
THIS_MAKEFILE := $(lastword $(MAKEFILE_LIST))
THIS_DIR := $(dir $(realpath $(THIS_MAKEFILE)))

.PHONY: manufacturing_release
manufacturing_release: release macrofab_release jlcpcb_release circuithub_release
	# Makes all manufacture releases and adds them to the output directory

include $(THIS_DIR)/jlcpcb.mk
include $(THIS_DIR)/macrofab.mk
include $(THIS_DIR)/circuithub.mk

