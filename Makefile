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
OUTDIR=${DIR}
KICADCLI=kicad-cli
# kicad-cli
#KICADCLI=flatpak run --command=kicad-cli org.kicad.KiCad
IBOM_SCRIPT=generate_interactive_bom
BOARD2PDF="/home/simon/.venv3-ssp/bin/board2pdf"
PYTHON="/usr/bin/python3"
KICAD_PYTHON_PATH=/usr/lib/kicad/lib/python3/dist-packages
BOM_SCRIPT=/usr/share/kicad/plugins/bom_csv_grouped_by_value.py
#PCBNEW_DO=pcbnew_do # Kiauto

TMP=/tmp
MANUFACTURING_DIR=${OUTDIR}/fab

SCH=${DIR}/${PROJECT}.kicad_sch
PCB=${DIR}/${PROJECT}.kicad_pcb
PCBBASE=$(basename $(notdir ${PCB}))
SCHBASE=$(basename $(notdir ${SCH}))

TIME=$(shell date +%s)

ASSEMBLY_DIR=${MANUFACTURING_DIR}/assembly
PDFSCH=${OUTDIR}/${SCHBASE}_${VERSION}.pdf
LOG=${OUTDIR}/log.log
MECH_DIR=${OUTDIR}/mechanical
XMLBOM=${ASSEMBLY_DIR}/${SCHBASE}_${VERSION}_BOM.xml
BOM=${ASSEMBLY_DIR}/${SCHBASE}_${VERSION}_BOM.csv
LCSCBOM=${ASSEMBLY_DIR}/${SCHBASE}_${VERSION}_LCSC_BOM.csv
ERC=${MANUFACTURING_DIR}/erc_${TIME}.rpt
DRC=${MANUFACTURING_DIR}/drc_${TIME}.rpt

# Visualizations
PDFSCH=${DIR}/${SCHBASE}_${VERSION}.pdf
IBOM=${DIR}/${PCBBASE}_${VERSION}_interactive_bom.html
GERBERPDF=${DIR}/${PCBBASE}_${VERSION}_gerbers.pdf

# BOMS & Assembly
CENTROID_CSV=${ASSEMBLY_DIR}/centroid.csv
CENTROID_GERBER=${ASSEMBLY_DIR}/centroid.gerber
JLC_CENTROID=${ASSEMBLY_DIR}/jlc-centroid.csv

IBOM=${OUTDIR}/${PCBBASE}_${VERSION}_interactive_bom.html
FABZIP=${OUTDIR}/${PCBBASE}_${VERSION}.zip
GENCAD=${OUTDIR}/${PCBBASE}_${VERSION}.cad
OUTLINE=${MECH_DIR}/board-outline.svg

# Manufacturing Files
DRILL=${MANUFACTURING_DIR}/gerbers/drill.drl
FABZIP=${DIR}/${PCBBASE}_${VERSION}.zip

# FIXME GENCAD cannot be exported with the command line
GENCAD=${DIR}/${PCBBASE}_${VERSION}.cad

# MECHANICAL
MECH_DIR=${DIR}/mechanical
STEP=${MECH_DIR}/${PCBBASE}_${VERSION}.step
OUTLINE=${MECH_DIR}/board-outline.svg

.PHONY: all
all: ${MECH_DIR} ${ASSEMBLY_DIR} schematic BOM ${GERBERPDF} manufacturing ${LCSCBOM}

.PHONY: no-drc
no-drc: schematic BOM ibom ${GERBERPDF} step gerbers board fabzip ipc2581

.PHONY: manufacturing
manufacturing: erc ibom step  drc gerbers board fabzip ipc2581

clean:
	-rm ${PDFSCH} ${XMLBOM} ${BOM} ${STEP} ${CENTROID_GERBER} ${CENTROID_CSV} ${JLC_CENTROID} ${IBOM} ${MANUFACTURING_DIR}/gerbers/*
	-rm ${FABZIP} kicad-cli ${OUTLINE}
	-rmdir ${MANUFACTURING_DIR}/gerbers ${MANUFACTURING_DIR}/assembly ${MANUFACTURING_DIR}
	-rmdir 3D mechanical

${DRC}: ${PCB} ${MANUFACTURING_DIR}
	${KICADCLI} pcb drc --exit-code-violations $< -o $@

${ERC}: ${SCH} ${MANUFACTURING_DIR}
	${KICADCLI} sch erc --exit-code-violations $< -o $@

# Generates schematic
${PDFSCH} : ${SCH}
	${KICADCLI} sch export pdf --black-and-white $< -o $@

# Generate python-BOM
${XMLBOM}: ${SCH} ${TMP}
	${KICADCLI} sch export python-bom $< -o $@

${BOM}: ${XMLBOM} ${ASSEMBLY_DIR}
	${PYTHON} ${BOM_SCRIPT}  $<  $@ > $@

${LCSCBOM}: ${ASSEMBLY_DIR} ${SCH}
	${KICADCLI} sch export bom ${SCH} --fields="Reference,Value,Footprint,LCSC,\$${QUANTITY},\$${DNP}" --labels="Ref Des,Value,Footprint,JLCPCB Part #,QUANTITY,DNP" --group-by="LCSC,\$${DNP},Value,Footprint" --ref-range-delimiter="" -o $@

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
