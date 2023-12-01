# Requires:
# 	+ KiAuto : https://github.com/INTI-CMNB/KiAuto
# 	+ KiCAD 7.0.0+
# 	+ InteractiveHtmlBOM : https://github.com/openscopeproject/InteractiveHtmlBom
#		+ KiKit: V 1.0.3+
#
#
#
# Tools & Tool Paths
DIR=$(shell pwd)
KICAD=kicad-cli
IBOM_SCRIPT=${HOME}/tools/InteractiveHtmlBom/InteractiveHtmlBom/generate_interactive_bom.py
PYTHON="/usr/bin/python3"
KICAD_PYTHON_PATH=/usr/lib/kicad/lib/python3/dist-packages
BOM_SCRIPT="/usr/share/kicad/plugins/bom_csv_grouped_by_value.py"
PCBNEW_DO=pcbnew_do # Kiauto
KIKIT=kikit

TMP=/tmp
MANUFACTURING_DIR=${DIR}/fab
DRC_RESULT=drc_result.rpt

# Project Information
PROJECT=PROJECTNAME
SCH=${DIR}/${PROJECT}.kicad_sch
PCB=${DIR}/${PROJECT}.kicad_pcb
PCBBASE=$(basename $(notdir ${PCB}))
SCHBASE=$(basename $(notdir ${SCH}))
VERSION=A.B.X

ASSEMBLY_DIR=${MANUFACTURING_DIR}/assembly
PDFSCH=${DIR}/${SCHBASE}_${VERSION}.pdf
LOG=${DIR}/log.log
MECH_DIR=${DIR}/mechanical
XMLBOM=${TMP}/${SCHBASE}_${VERSION}_BOM.xml
BOM=${ASSEMBLY_DIR}/${SCHBASE}_${VERSION}_BOM.csv
LCSCBOM=${ASSEMBLY_DIR}/${SCHBASE}_${VERSION}_LCSC_BOM.csv

DRILL=${MANUFACTURING_DIR}/gerbers/drill.drl
STEP=${MECH_DIR}/${PCBBASE}_${VERSION}.step
CENTROID_CSV=${ASSEMBLY_DIR}/centroid.csv
CENTROID_GERBER=${ASSEMBLY_DIR}/centroid.gerber
JLC_CENTROID=${ASSEMBLY_DIR}/jlc-centroid.csv
IBOM=${DIR}/${PCBBASE}_${VERSION}_interactive_bom.html
FABZIP=${DIR}/${PCBBASE}_${VERSION}.zip
GENCAD=${DIR}/${PCBBASE}_${VERSION}.cad
OUTLINE=${MECH_DIR}/board-outline.svg


export PYTHONPATH=


.PHONY: all
all: ${MECH_DIR} ${ASSEMBLY_DIR} schematic BOM manufacturing

.PHONY: no-drc
no-drc: schematic BOM ibom step gerbers board fabzip

.PHONY: manufacturing
manufacturing: ibom step drc gerbers board fabzip

clean:
	-rm ${PDFSCH} ${XMLBOM} ${BOM} ${STEP} ${CENTROID_GERBER} ${CENTROID_CSV} ${JLC_CENTROID} ${IBOM} ${MANUFACTURING_DIR}/gerbers/*
	-rm ${FABZIP} kicad-cli ${OUTLINE}
	-rmdir ${MANUFACTURING_DIR}/gerbers ${MANUFACTURING_DIR}/assembly ${MANUFACTURING_DIR}
	-rmdir 3D mechanical


drc: ${PCB}
	${KIKIT} drc run $<
	#${PCBNEW_DO} run_drc $< ./ >> ${DIR}/log.log

erc: ${SCH}
	${PCBNEW_DO} run_erc $< ./ >> ${DIR}/log.log

# Generates schematic
${PDFSCH} : ${SCH}
	${KICAD} sch export pdf --black-and-white $< -o $@


# Generate python-BOM
${XMLBOM}: ${SCH} ${TMP}
	${KICAD} sch export python-bom $< -o $@


${BOM}: ${XMLBOM} ${ASSEMBLY_DIR}
	${PYTHON} ${BOM_SCRIPT}  $<  $@ > $@

${MANUFACTURING_DIR}:
	mkdir -p $@

${ASSEMBLY_DIR}: ${MANUFACTURING_DIR}
	mkdir -p $@

# Complains about output needing to be a directory, work around this
${DRILL}: ${PCB}
	mkdir -p ${MANUFACTURING_DIR}/gerbers
	${KICAD} pcb export drill --excellon-units mm $< -o ./
	mv ${PCBBASE}.drl $@


${CENTROID_CSV}: ${PCB} ${ASSEMBLY_DIR}
	${KICAD} pcb export pos --use-drill-file-origin --side both --format csv --units mm $< -o $@

${JLC_CENTROID}: ${CENTROID_CSV} ${ASSEMBLY_DIR}
	#echo "Ref,Val,Package,PosX,PosY,Rot,Side" >> 
	echo "Designator,Comment,Footprint,Mid X,Mid Y,Rotation,Layer" > $@
	tail --lines=+2 $< >> $@

${MECH_DIR}:
	mkdir -p ${MECH_DIR}

${STEP}: ${PCB} ${MECH_DIR}
	${KICAD} pcb export step $< --drill-origin --subst-models -f -o $@


gerbers: ${PCB} ${MANUFACTURING_DIR}#drc
	mkdir -p ${MANUFACTURING_DIR}/gerbers
	${KICAD} pcb export gerbers --subtract-soldermask --use-drill-file-origin $< -o ${MANUFACTURING_DIR}/gerbers


${IBOM}: ${PCB}
	${IBOM_SCRIPT} $< --dnp-field DNP --group-fields "Value,Footprint" --blacklist "X1,MH*" --include-nets --normalize-field-case --no-browser --dest-dir ./ --name-format %f_%r_interactive_bom


${FABZIP}: board
	zip -rj $@ ${MANUFACTURING_DIR}/gerbers
	

# Board Outline
${OUTLINE}: ${PCB}
	${KICAD} pcb export svg -l "Edge.Cuts" --black-and-white --exclude-drawing-sheet $< -o $@


gencad: gerbers
	${KICAD} pcb export gencad -l "Edge.Cuts" --black-and-white --exclude-drawing-sheet $< -o $@

# Add board renders

# Add expanding BOMs

#.PHONY: jlcpcbbom
#jlcpcbbom: ${LCSCBOM}

# Add placement from spreadsheet
.PHONY: place
place: ${}

.PHONY: zip
zip: ${FABZIP}

.PHONY: step
step: ${STEP}

.PHONY: ibom
ibom: ${IBOM}

.PHONY: schematic
schematic : ${PDFSCH}

.PHONY: BOM
BOM: ${BOM}

.PHONY: fabzip
fabzip: ${FABZIP}

.PHONY: board
board: gerbers ${DRILL} ${CENTROID_CSV} ${JLC_CENTROID} ${ASSEMBLY_BOM} ${OUTLINE}

.PHONY: setup
setup: ${ASSEMBLY_BOM} ${BOM} schematic ibom step
