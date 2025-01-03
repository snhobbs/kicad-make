# Requires:
# 	+ KiCAD 8.0.0+
# 	+ InteractiveHtmlBOM : https://github.com/openscopeproject/InteractiveHtmlBom
# 		+ Improved Packaging Version: https://github.com/snhobbs/InteractiveHtmlBom

# Project Information. Call this make file with those values set
PROJECT=PROJECTNAME
VERSION=A.B.X

ROOT_DIR:=$(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))

# Tools & Tool Paths
DIR=$(abspath $(shell pwd))
OUTDIR=$(abspath ${DIR})
_DIR=$(abspath ${DIR})
_OUTDIR=$(abspath ${OUTDIR})

KICADCLI=kicad-cli
#KICADCLI=flatpak run --command=kicad-cli org.kicad.KiCad
#KICADCLI=flatpak run --share=network --filesystem=home:rw --command=/app/bin/kicad-cli -- org.kicad.KiCad
IBOM_SCRIPT=generate_interactive_bom
BOARD2PDF=board2pdf
PYTHON="/usr/bin/python3"
KICAD_PYTHON_PATH=/usr/lib/python3/dist-packages/_pcbnew.so
BOM_SCRIPT=/usr/share/kicad/plugins/bom_csv_grouped_by_value.py
#BOM_SCRIPT=/home/simon/tools/kicad-source-mirror/eeschema/python_scripts/bom_csv_grouped_by_value.py
LOGS_DIR=${_OUTDIR}/logs
TMP=/tmp
MANUFACTURING_DIR=${_OUTDIR}/fab

SCH=${_DIR}/${PROJECT}.kicad_sch
PCB=${_DIR}/${PROJECT}.kicad_pcb
PCBBASE=$(basename $(notdir ${PCB}))
SCHBASE=$(basename $(notdir ${SCH}))

TIME=$(shell date +%s)

ASSEMBLY_DIR=${MANUFACTURING_DIR}/assembly
LOG=${_DIR}/log.log
MECH_DIR=${_OUTDIR}/mechanical
XMLBOM=${ASSEMBLY_DIR}/${SCHBASE}_${VERSION}_BOM.xml
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

IBOM=${_OUTDIR}/${PCBBASE}_${VERSION}_interactive_bom.html
FABZIP=${_OUTDIR}/${PCBBASE}_${VERSION}.zip
GENCAD=${_OUTDIR}/${PCBBASE}_${VERSION}.cad
OUTLINE=${MECH_DIR}/board-outline.svg

# Manufacturing Files
DRILL=${MANUFACTURING_DIR}/gerbers/drill.drl
FABZIP=${_OUTDIR}/${PCBBASE}_${VERSION}.zip

# FIXME GENCAD cannot be exported with the command line
GENCAD=${_OUTDIR}/${PCBBASE}_${VERSION}.cad

# MECHANICAL
MECH_DIR=${_OUTDIR}/mechanical
STEP=${MECH_DIR}/${PCBBASE}_${VERSION}.step
OUTLINE=${MECH_DIR}/board-outline.svg

.PHONY: all
all: ${MECH_DIR} ${ASSEMBLY_DIR} schematic BOM gerberpdf manufacturing ${LCSCBOM}

.PHONY: manufacturing
manufacturing: erc ibom gerberpdf step drc gerbers board fabzip ipc2581

.PHONY: no-drc
no-drc: ${MECH_DIR} ${ASSEMBLY_DIR} schematic BOM gerberpdf ibom gerberpdf step gerbers board fabzip ipc2581 ${LCSCBOM}

clean:
	-rm ${PDFSCH} ${XMLBOM} ${BOM} ${STEP} ${CENTROID_GERBER} ${CENTROID_CSV} ${JLC_CENTROID} ${IBOM} ${MANUFACTURING_DIR}/gerbers/*
	-rm ${FABZIP} ${OUTLINE}
	-rm -r ${LOGS_DIR}
	-rm -r ${LCSCBOM}
	-rmdir ${MANUFACTURING_DIR}/gerbers ${MANUFACTURING_DIR}/assembly ${MANUFACTURING_DIR}
	-rmdir mechanical


.PHONY: ${DRC}
${DRC}: ${PCB} ${LOGS_DIR} ${ERC}
	${KICADCLI} pcb drc --exit-code-violations $< -o $@

.PHONY: ${ERC}
${ERC}: ${SCH} ${LOGS_DIR}
	${KICADCLI} sch erc --exit-code-violations $< -o $@

SCHEMATIC_FLAGS=--black-and-white --drawing-sheet /home/simon/EOI/heoDocs/Templates/Kicad_A4.kicad_wks
# Generates schematic
${PDFSCH} : ${SCH}
	${KICADCLI} sch export pdf ${SCHEMATIC_FLAGS} $< -o $@

# Generate python-BOM
${XMLBOM}: ${SCH} ${TMP}
	${KICADCLI} sch export python-bom $< -o $@

${BOM}: ${XMLBOM} ${ASSEMBLY_DIR}
	${PYTHON} ${BOM_SCRIPT}  $<  $@ > $@

${LCSCBOM}: ${ASSEMBLY_DIR} ${SCH}
	${KICADCLI} sch export bom ${SCH} --fields="Reference,Value,Footprint,LCSC,\$${QUANTITY},\$${DNP}" --labels="Ref Des,Value,Footprint,JLCPCB Part #,QUANTITY,DNP" --group-by="LCSC,\$${DNP},Value,Footprint" --ref-range-delimiter="" -o $@

${LOGS_DIR}: ${_OUTDIR}
	mkdir -p $@

${MANUFACTURING_DIR}:
	mkdir -p $@

${ASSEMBLY_DIR}: ${MANUFACTURING_DIR}
	mkdir -p $@

# Complains about output needing to be a directory, work around this
${DRILL}: ${PCB}
	mkdir -p ${MANUFACTURING_DIR}/gerbers
	${KICADCLI} pcb export drill --drill-origin plot --excellon-units mm $< -o ./
	mv ${PCBBASE}.drl $@

${CENTROID_CSV}: ${PCB} ${ASSEMBLY_DIR}
	${KICADCLI} pcb export pos --use-drill-file-origin --side both --format csv --units mm $< -o $@

${JLC_CENTROID}: ${CENTROID_CSV} ${ASSEMBLY_DIR}
	#echo "Ref,Val,Package,PosX,PosY,Rot,Side" >>
	echo "Designator,Comment,Footprint,Mid X,Mid Y,Rotation,Layer" > $@
	tail --lines=+2 $< >> $@

${MECH_DIR}:
	mkdir -p ${MECH_DIR}

${STEP}: ${PCB} ${MECH_DIR}
	${KICADCLI} pcb export step $< --drill-origin --subst-models -f -o $@

gerbers: ${PCB} ${MANUFACTURING_DIR}#drc
	mkdir -p ${MANUFACTURING_DIR}/gerbers
	${KICADCLI} pcb export gerbers --subtract-soldermask --use-drill-file-origin $< -o ${MANUFACTURING_DIR}/gerbers

# Screen size required for running headless
# https://github.com/openscopeproject/InteractiveHtmlBom/wiki/Tips-and-Tricks
# NOTE: The version in this file is taken from the PCB title block and may not match
# the delared version. These need to be adjusted manually.
${IBOM}: ${PCB}
	xvfb-run --auto-servernum --server-args "-screen 0 1024x768x24" ${IBOM_SCRIPT} $< --dnp-field DNP --group-fields "Value,Footprint" --blacklist "X1,MH*" --include-nets --normalize-field-case --no-browser --dest-dir ./ --name-format $(basename $@ .html)

${FABZIP}: board
	zip -rj $@ ${MANUFACTURING_DIR}/gerbers

# Board Outline
${OUTLINE}: ${PCB}
	${KICADCLI} pcb export svg -l "Edge.Cuts" --black-and-white --exclude-drawing-sheet $< -o $@

${GERBERPDF}: ${PCB}
	${BOARD2PDF} $< --output $@ --ini ${ROOT_DIR}/board2pdf.config.ini 

.PHONY: ipc2581
ipc2581: ${PCB}
	${KICADCLI} pcb export ipc2581 $<

.PHONY: fabzip
fabzip: ${FABZIP}

.PHONY: drc
drc: ${DRC}

.PHONY: erc
erc: ${ERC}

.PHONY: LCSCBOM
LCSCBOM: ${LCSCBOM}

.PHONY: zip
zip: ${FABZIP}

.PHONY: step
step: ${STEP}

.PHONY: ibom
ibom: ${IBOM}

.PHONY: schematic
schematic : ${PDFSCH}

.PHONY: BOM
BOM: ${BOM} ${LCSCBOM}

.PHONY: XMLBOM
XMLBOM: ${XMLBOM}

.PHONY: fabzip
fabzip: ${FABZIP}

.PHONY: board
board: gerbers ${DRILL} ${CENTROID_CSV} ${JLC_CENTROID} ${ASSEMBLY_BOM} ${OUTLINE}

.PHONY: setup
setup: ${ASSEMBLY_BOM} ${BOM} schematic ibom step

.PHONY: gerberpdf
gerberpdf: ${GERBERPDF}

.PHONY: centroid
centroid: ${CENTROID} ${JLC_CENTROID}
