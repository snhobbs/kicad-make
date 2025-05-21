# Project Information. Call this make file with those values set
#===============================================================
ifndef PROJECT
$(error PROJECT is not set)
endif
ifndef VERSION
$(error VERSION is not set)
endif
#===============================================================


# Values you may want to change
#===============================================================
ROOT_DIR:=$(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
DIR=$(abspath $(shell pwd))
OUTDIR=$(abspath ${DIR})
#===============================================================


# Tools & Tool Paths, change these if your path is different
#===============================================================
# kicad-cli
KICADCLI=kicad-cli
#	flatpak
#	KICADCLI=flatpak run --command=kicad-cli org.kicad.KiCad
#	snap
#	KICADCLI=/snap/bin/kicad.kicad-cli
#	docker
#KICADCLI=docker run -v /tmp/.X11-unix:/tmp/.X11-unix -v ${HOME}:${HOME} -it --rm -e DISPLAY=:0 --name kicad-cli kicad/kicad:8.0 kicad-cli
IBOM_SCRIPT=generate_interactive_bom
BOARD2PDF_SCRIPT=board2pdf
#===============================================================

SCH_DRAWING_SHEET=S{ROOT_DIR}/SchDrawingSheet.kicad_wks
PCB_DRAWING_SHEET=${SCH_DRAWING_SHEET}
#===============================================================

_DIR=$(abspath ${DIR})
_OUTDIR=$(abspath ${OUTDIR})
MANUFACTURING_DIR=${_OUTDIR}/fab
ASSEMBLY_DIR=${MANUFACTURING_DIR}/assembly
GERBER_DIR=${MANUFACTURING_DIR}/gerbers
LOGS_DIR=${_OUTDIR}/logs
MECH_DIR=${_OUTDIR}/mechanical
GERBERPDF_INI=${ROOT_DIR}/board2pdf.config.ini

TIME=$(shell date +%s)
COMMA := ,
SPACE := $(empty) $(empty)

SCH=${_DIR}/${PROJECT}.kicad_sch
PCB=${_DIR}/${PROJECT}.kicad_pcb
PCBBASE=$(basename $(notdir ${PCB}))
SCHBASE=$(basename $(notdir ${SCH}))

BOM=${ASSEMBLY_DIR}/${SCHBASE}_${VERSION}_BOM.csv
LCSCBOM=${ASSEMBLY_DIR}/${SCHBASE}_${VERSION}_LCSC_BOM.csv
ERC=${LOGS_DIR}/erc.rpt
DRC=${LOGS_DIR}/drc.rpt

# Visualizations
PDFSCH=${_OUTDIR}/${SCHBASE}_${VERSION}.pdf
IBOM=${_OUTDIR}/${PCBBASE}_${VERSION}_interactive_bom.html
GERBERPDF=${_OUTDIR}/${PCBBASE}_${VERSION}_gerbers.pdf

# BOMS & Assembly
CENTROID_CSV=${ASSEMBLY_DIR}/centroid.csv
CENTROID_GERBER=${ASSEMBLY_DIR}/centroid.gerber
JLC_CENTROID=${ASSEMBLY_DIR}/jlc-centroid.csv

# Manufacturing Files
DRILL=${MANUFACTURING_DIR}/gerbers/drill.drl
FABZIP=${_OUTDIR}/${PCBBASE}_${VERSION}.zip
IPC2581=${_OUTDIR}/IPC2581_${PCBBASE}_${VERSION}.xml
TESTPOINT_REPORT=${_OUTDIR}/testpoints_${PCBBASE}_${VERSION}.csv
NETLIST=${_OUTDIR}/netlist_${PCBBASE}_${VERSION}.csv

# MECHANICAL
MECH_DIR=${_OUTDIR}/mechanical
STEP=${MECH_DIR}/${PCBBASE}_${VERSION}.step
OUTLINE=${MECH_DIR}/board-outline.svg

.PHONY: release
release: ${MECH_DIR} ${ASSEMBLY_DIR} manufacturing fabzip

.PHONY: release manufacturing no-drc clean
release: erc drc manufacturing fabzip

manufacturing: ${GERBER_DIR} ${MECH_DIR} ${ASSEMBLY_DIR} schematic boms gerberpdf ibom step gerbers board ipc2581 testpoints
	echo "\n\n Manufacturing Files Exported \n\n"

no-drc: manufacturing fabzip

clean:
	-rm ${GERBERPDF}
	-rm ${PDFSCH}
	-rm ${BOM}
	-rm ${STEP}
	-rm ${CENTROID_GERBER}
	-rm ${CENTROID_CSV}
	-rm ${JLC_CENTROID}
	-rm ${IBOM}
	-rm ${GERBER_DIR}/*.gbr
	-rm ${FABZIP}
	-rm ${OUTLINE}
	-rm ${LOGS_DIR}/*.log
	-rm ${LOGS_DIR}/*.rpt
	-rm ${LCSCBOM}
	-rm ${IPC2581}
	-rm -r ${GERBER_DIR}
	-rmdir ${MECH_DIR}
	-rmdir ${GERBER_DIR} ${ASSEMBLY_DIR} ${MANUFACTURING_DIR} ${GERBER_PDF_DIR} ${LOGS_DIR}


${TESTPOINT_REPORT}: ${PCB} | ${_OUTDIR}
	kicad_testpoints by-fab-setting --pcb "$<" --out "$@"

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
	${KICADCLI} sch export bom "$<" --fields "Reference,Value,Footprint,\$${QUANTITY},\$${DNP},MPN,LCSC,Notes" --group-by="\$${DNP},Value,Footprint" --ref-range-delimiter="" -o "$@"

${LCSCBOM}: ${SCH} | ${ASSEMBLY_DIR}
	${KICADCLI} sch export bom "$<" --fields="Reference,Value,Footprint,LCSC,\$${QUANTITY},\$${DNP}" --labels="Ref Des,Value,Footprint,JLCPCB Part #,QUANTITY,DNP" --group-by="LCSC,\$${DNP},Value,Footprint" --ref-range-delimiter="" -o "$@"

${LOGS_DIR}: | ${_OUTDIR}
	mkdir -p "$@"

${MANUFACTURING_DIR}: | ${_OUTDIR}
	mkdir -p "$@"

${ASSEMBLY_DIR}: | ${MANUFACTURING_DIR}
	mkdir -p "$@"

${GERBER_DIR}: | ${MANUFACTURING_DIR}
	mkdir -p "$@"

${MECH_DIR}: | ${MANUFACTURING_DIR}
	mkdir -p "$@"

${_OUTDIR}:
	mkdir -p "$@"

# Complains about output needing to be a directory, work around this
${DRILL}: ${PCB} | ${GERBER_DIR}
	${KICADCLI} pcb export drill --drill-origin plot --excellon-units mm "$<" -o ${GERBER_DIR}
	mv ${GERBER_DIR}/${PCBBASE}.drl "$@"

${CENTROID_CSV}: ${PCB} | ${ASSEMBLY_DIR}
	${KICADCLI} pcb export pos --use-drill-file-origin --side both --format csv --units mm "$<" -o "$@"

${JLC_CENTROID}: ${CENTROID_CSV} | ${ASSEMBLY_DIR}
	#echo "Ref,Val,Package,PosX,PosY,Rot,Side" >>
	echo "Designator,Comment,Footprint,Mid X,Mid Y,Rotation,Layer" > "$@"
	tail --lines=+2 "$<" >> "$@"

${STEP}: ${PCB} | ${MECH_DIR}
	${KICADCLI} pcb export step "$<" --drill-origin --subst-models -f -o "$@"

# Screen size required for running headless
# https://github.com/openscopeproject/InteractiveHtmlBom/wiki/Tips-and-Tricks
${IBOM}: ${PCB} | ${ASSEMBLY_DIR}
	xvfb-run --auto-servernum --server-args "-screen 0 1024x768x24" ${IBOM_SCRIPT} "$<" \
		--dnp-field DNP --group-fields "Value,Footprint" --blacklist "X1,MH*" \
		--include-nets --normalize-field-case --no-browser --dest-dir ./ \
		--name-format "$(basename $@ )"

${FABZIP}: ${GERBER_DIR}
	zip -rj "$@" "$<"

${OUTLINE}: ${PCB} | ${MECH_DIR}
	${KICADCLI} pcb export svg -l "Edge.Cuts" --black-and-white --exclude-drawing-sheet "$<" -o "$@"

${GERBERPDF}: ${PCB} | ${_OUTDIR}
	${BOARD2PDF_SCRIPT} "$<" --output "$@" --ini ${GERBERPDF_INI}

${_OUTDIR}/${PCBBASE}_${VERSION}_Render_%.png: ${PCB} | ${_OUTDIR}
	${KICADCLI} pcb render --side $(shell echo $* | tr A-Z a-z) --background transparent --quality high "$<" -o "$@"

${IPC2581}: ${PCB} | ${_OUTDIR}
	${KICADCLI} pcb export ipc2581 "$<" -o "$@"

gerbers: ${PCB} | ${GERBER_DIR}
	${KICADCLI} pcb export gerbers --use-drill-file-origin "$<" -o ${GERBER_DIR}

ipc2581: ${IPC2581}

fabzip: ${FABZIP}

drc: ${DRC}

erc: ${ERC}

LCSCBOM: ${LCSCBOM}

zip: ${FABZIP}

step: ${STEP}

ibom: ${IBOM}

schematic: ${PDFSCH}

boms: ${ASSEMBLY_DIR} ${BOM} ${LCSCBOM} ${ASSEMBLY_BOM} ibom

board: gerbers ${DRILL} ${CENTROID_CSV} ${JLC_CENTROID} boms ${OUTLINE}

setup: boms schematic ibom step

gerberpdf: ${GERBERPDF}

centroid: ${CENTROID} ${JLC_CENTROID}

erc: ${ERC}

drc: ${DRC}

testpoints: ${TESTPOINT_REPORT}

.PHONY: gerbers ipc2581 fabzip drc erc LCSCBOM zip step ibom schematic boms board setup gerberpdf centroid erc drc testpoints
