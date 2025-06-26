# Base Makefile, there are additional Makefiles for specific output configurations and manufacturers
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

#===============================================================
# Directory Paths & Tool Paths
#===============================================================
ROOT_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
DIR := $(abspath $(shell pwd))
OUTDIR = $(abspath ${DIR})
MANUFACTURING_DIR = ${_OUTDIR}/fab
ASSEMBLY_DIR = ${MANUFACTURING_DIR}/assembly
GERBER_DIR = ${MANUFACTURING_DIR}/gerbers
LOGS_DIR = ${_OUTDIR}/logs
MECH_DIR = ${_OUTDIR}/mechanical

# Tool paths
KICADCLI=kicad-cli
IBOM_SCRIPT=generate_interactive_bom
KICAD_TESTPOINTS_SCRIPT=kicad_testpoints

# Drawing Sheet Paths
SCH_DRAWING_SHEET = ${ROOT_DIR}/SchDrawingSheet.kicad_wks
PCB_DRAWING_SHEET = ${SCH_DRAWING_SHEET}


#===============================================================
# Generated File Paths
#===============================================================
_DIR=$(abspath ${DIR})
_OUTDIR=$(abspath ${OUTDIR})

SCH=${_DIR}/${PROJECT}.kicad_sch
PCB=${_DIR}/${PROJECT}.kicad_pcb
PCBBASE=$(basename $(notdir ${PCB}))
SCHBASE=$(basename $(notdir ${SCH}))

BOM=${ASSEMBLY_DIR}/${SCHBASE}_${VERSION}_BOM.csv
ERC=${LOGS_DIR}/erc.rpt
DRC=${LOGS_DIR}/drc.rpt

# Visualizations
PDFSCH=${_OUTDIR}/${SCHBASE}_${VERSION}_schematic.pdf
IBOM=${_OUTDIR}/${PCBBASE}_${VERSION}_interactive_bom.html
GERBER_PDF_DIR=${_OUTDIR}/gerberpdf
GERBERPDF=${_OUTDIR}/${PCBBASE}_${VERSION}_gerbers.pdf
RENDER_DIR=${_OUTDIR}/renders
RENDERS:= ${RENDER_DIR}/Render_TOP.png \
		   ${RENDER_DIR}/Render_BOTTOM.png \
		   ${RENDER_DIR}/Render_LEFT.png \
		   ${RENDER_DIR}/Render_RIGHT.png \
		   ${RENDER_DIR}/Render_FRONT.png \
		   ${RENDER_DIR}/Render_BACK.png

# BOMS & Assembly
CENTROID_CSV=${ASSEMBLY_DIR}/centroid.csv
CENTROID_GERBER=${ASSEMBLY_DIR}/centroid.gerber

# Manufacturing Files
DRILL=${MANUFACTURING_DIR}/gerbers/drill.drl
FABZIP=${_OUTDIR}/${PCBBASE}_${VERSION}_manufacturing.zip
IPC2581=${_OUTDIR}/IPC2581_${PCBBASE}_${VERSION}.xml
GENCAD=${_OUTDIR}/GENCAD_${PCBBASE}_${VERSION}.cad
ODB=${_OUTDIR}/ODB_${PCBBASE}_${VERSION}.zip
IPC2581=${MANUFACTURING_DIR}/IPC2581_${PCBBASE}_${VERSION}.xml
TESTPOINT_REPORT=${_OUTDIR}/testpoints_${PCBBASE}_${VERSION}.csv
NETLIST=${_OUTDIR}/netlist_${PCBBASE}_${VERSION}.csv

# MECHANICAL
MECH_DIR=${_OUTDIR}/mechanical
STEP=${MECH_DIR}/${PCBBASE}_${VERSION}.step
OUTLINE=${MECH_DIR}/board-outline.svg

TIME=$(shell date +%s)
COMMA:= ,
SPACE:= $(empty) $(empty)

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


${TESTPOINT_REPORT}: ${PCB} | ${_OUTDIR}
	${KICAD_TESTPOINTS_SCRIPT} by-fab-setting --pcb "$<" --out "$@"

# Move the log file to the final location if the command succeeds so it doesn't rerun
${DRC}: ${PCB} ${ERC} | ${LOGS_DIR}
	${KICADCLI} pcb drc --exit-code-violations "$<" -o ${LOGS_DIR}/drc-out.log
	mv ${LOGS_DIR}/drc-out.log "$@"

${ERC}: ${SCH} | ${LOGS_DIR}
	${KICADCLI} sch erc --exit-code-violations "$<" -o ${LOGS_DIR}/erc-out.log
	mv ${LOGS_DIR}/erc-out.log "$@"

# Generates schematic
${PDFSCH} : ${SCH} | ${_OUTDIR}
	${KICADCLI} sch export pdf --black-and-white --drawing-sheet ${SCH_DRAWING_SHEET} "$<" -o "$@"

${BOM}: ${SCH} | ${ASSEMBLY_DIR}
	${KICADCLI} sch export bom "$<" --fields "Reference,Value,Footprint,\$${QUANTITY},\$${DNP},Manufacturers Part Number,MPN,Notes" --group-by="\$${DNP},Value,Footprint,Manufacturers Part Number" --ref-range-delimiter="" -o "$@"

# Complains about output needing to be a directory, work around this
${DRILL}: ${PCB} | ${GERBER_DIR}
	${KICADCLI} pcb export drill --drill-origin plot --excellon-units mm "$<" -o ${GERBER_DIR}
	mv ${GERBER_DIR}/${PCBBASE}.drl "$@"

${CENTROID_CSV}: ${PCB} | ${ASSEMBLY_DIR}
	${KICADCLI} pcb export pos --use-drill-file-origin --side both --format csv --units mm "$<" -o "$@"

${STEP}: ${PCB} | ${MECH_DIR}
	${KICADCLI} pcb export step "$<" --drill-origin --subst-models -f -o "$@"

# Screen size required for running headless
# https://github.com/openscopeproject/InteractiveHtmlBom/wiki/Tips-and-Tricks
${IBOM}: ${PCB} | ${ASSEMBLY_DIR}
	xvfb-run --auto-servernum --server-args "-screen 0 1024x768x24" ${IBOM_SCRIPT} "$<" \
		--dnp-field DNP --group-fields "Value,Footprint" --blacklist "X1,MH*" \
		--include-nets --normalize-field-case --no-browser --dest-dir ./ \
		--name-format "$(basename $@ )"

${FABZIP}: ${MANUFACTURING_DIR} ${CENTROID_CSV} gerbers ${IPC2581} boms
	zip -rj "$@" "$<"

${OUTLINE}: ${PCB} | ${MECH_DIR}
	${KICADCLI} pcb export svg -l "Edge.Cuts" --black-and-white --exclude-drawing-sheet "$<" -o "$@"

${RENDER_DIR}/Render_%.png: ${PCB} | ${_OUTDIR} ${RENDER_DIR}
	${KICADCLI} pcb render --side $(shell echo $* | tr A-Z a-z) --background transparent --quality high "$<" -o "$@"

${IPC2581}: ${PCB} | ${_OUTDIR}
	${KICADCLI} pcb export ipc2581 "$<" -o "$@"

${GERBERPDF}: ${PCB} | ${GERBER_PDF_DIR}
	${KICADCLI} pcb export pdf ${PCB} --black-and-white \
		--cl "Edge.Cuts" \
		-l ${PDF_GERBER_LAYERS_CSV} \
		-o ${GERBER_PDF_DIR} \
		--drawing-sheet ${PCB_DRAWING_SHEET} \
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

${_OUTDIR}/${PCBBASE}_${VERSION}_Render_%.png: ${PCB} | ${_OUTDIR}
	${KICADCLI} pcb render \
		--side $(shell echo $* | tr A-Z a-z) \
		--background transparent \
		--quality high "$<" -o "$@"

${GENCAD}: ${PCB} | ${_OUTDIR}
	${KICADCLI} pcb export gencad "$<" -o "$@"

${ODB}: ${PCB} | ${_OUTDIR}
	${KICADCLI} pcb export odb "$<" -o "$@"

gerbers: ${PCB} | ${GERBER_DIR}
	${KICADCLI} pcb export gerbers --use-drill-file-origin "$<" -o ${GERBER_DIR}

#===============================================================
# Compund Targets
#===============================================================

.PHONY: release gerbers odb gencad ipc2581 fabzip drc erc zip step ibom schematic boms board gerberpdf centroid erc drc testpoints manufacturing no-drc documents

release: erc drc manufacturing fabzip documents

documents: schematic boms gerberpdf ibom step renders

manufacturing: ${GERBER_DIR} ${MECH_DIR} ${ASSEMBLY_DIR} gerbers board ipc2581 odb gencad testpoints
	echo "\n\n Manufacturing Files Exported \n\n"

no-drc: documents manufacturing fabzip

centroid: ${CENTROID} ${JLC_CENTROID}

boms: ${ASSEMBLY_DIR} ${BOM} ${ASSEMBLY_BOM} ibom

board: gerbers ${DRILL} ${CENTROID_CSV} boms ${OUTLINE}

#===============================================================
# Aliased Targets
#===============================================================

ipc2581: ${IPC2581}

odb: ${ODB}

gencad: ${GENCAD}

drc: ${DRC}

erc: ${ERC}

fabzip: ${FABZIP}

step: ${STEP}

ibom: ${IBOM}

schematic: ${PDFSCH}

gerberpdf: ${GERBERPDF}

testpoints: ${TESTPOINT_REPORT}

renders: ${RENDERS}


#===============================================================
# Manufacturer Targets
#===============================================================
THIS_MAKEFILE := $(lastword $(MAKEFILE_LIST))
THIS_DIR := $(dir $(realpath $(THIS_MAKEFILE)))

.PHONY: manufacturing_release 
manufacturing_release: release macrofab_release jlcpcb_release
	# Makes all manufacture releases and adds them to the output directory

include $(THIS_DIR)/jlcpcb.mk
include $(THIS_DIR)/macrofab.mk

