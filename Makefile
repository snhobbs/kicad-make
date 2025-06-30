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

.PHONY: all clean
all: release


#===============================================================
# Create Directories if Not Exist
#===============================================================
$(LOGS_DIR) $(MANUFACTURING_DIR) $(ASSEMBLY_DIR) $(GERBER_DIR) $(MECH_DIR) $(OUTDIR):
	mkdir -p $@

#===============================================================
# Clean Up Generated Files
#===============================================================
clean:
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

${IPC2581}: ${PCB} | ${_OUTDIR}
	${KICADCLI} pcb export ipc2581 "$<" -o "$@"

gerbers: ${PCB} | ${GERBER_DIR}
	${KICADCLI} pcb export gerbers --use-drill-file-origin "$<" -o ${GERBER_DIR}

#===============================================================
# Compund Targets
#===============================================================

.PHONY: release gerbers ipc2581 fabzip drc erc zip step ibom schematic boms board centroid erc drc testpoints manufacturing no-drc documents

release: erc drc manufacturing fabzip documents

documents: schematic boms ibom step

manufacturing: ${GERBER_DIR} ${MECH_DIR} ${ASSEMBLY_DIR} gerbers board ipc2581 testpoints
	echo "\n\n Manufacturing Files Exported \n\n"

no-drc: documents manufacturing fabzip

centroid: ${CENTROID}

boms: ${ASSEMBLY_DIR} ${BOM} ${ASSEMBLY_BOM}

board: gerbers ${DRILL} ${CENTROID_CSV} boms ${OUTLINE}

#===============================================================
# Aliased Targets
#===============================================================

ipc2581: ${IPC2581}

drc: ${DRC}

erc: ${ERC}

fabzip: ${FABZIP}

step: ${STEP}

ibom: ${IBOM}

schematic: ${PDFSCH}

testpoints: ${TESTPOINT_REPORT}


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

