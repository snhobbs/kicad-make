# Tools & Tool Paths
KICAD=kicad-cli
IBOM_SCRIPT=${HOME}/tools/InteractiveHtmlBom/InteractiveHtmlBom/generate_interactive_bom.py
PYTHON="/usr/bin/python3"
KICAD_PYTHON_PATH=/usr/lib/kicad/lib/python3/dist-packages
BOM_SCRIPT="/usr/share/kicad/plugins/bom_csv_grouped_by_value.py"
TMP=/tmp
MANUFACTURING_DIR=fab
PCBNEW_DO=pcbnew_do

# Project Information
PROJECT=PROJECT_NAME
VERSION=A.B.X
SCH=${PROJECT}.kicad_sch
PCB=${PROJECT}.kicad_pcb

SCHBASE=$(basename ${SCH})
PCBBASE=$(basename ${PCB})
PDFSCH=${SCHBASE}.pdf
LOG=log.log

XMLBOM=${TMP}/${SCHBASE}_${VERSION}_BOM.xml
BOM=${MANUFACTURING_DIR}/assembly/${SCHBASE}_${VERSION}_BOM.csv

DRILL=${MANUFACTURING_DIR}/gerbers/drill.drl
STEP=3D/${PCBBASE}_${VERSION}.step
CENTROID=${MANUFACTURING_DIR}/assembly/centroid.csv
IBOM=${PCBBASE}_${VERSION}_interactive_bom.html
FABZIP=${PCBBASE}_${VERSION}.zip


export PYTHONPATH=${KICAD_PYTHON_PATH}


.PHONY: all
all: schematic BOM gerbers ibom board step fabzip

clean:
	rm ${DRILL} 
	rm ${PDFSCH} ${XMLBOM} ${BOM} ${STEP} ${CENTROID} ${IBOM} ${MANUFACTURING_DIR}/gerbers/*
	rm ${FABZIP}
	rmdir ${MANUFACTURING_DIR}/gerbers ${MANUFACTURING_DIR}/assembly ${MANUFACTURING_DIR}
	rmdir tmp 3D 


# Generates schematic
${PDFSCH} : ${SCH}
	${KICAD} sch export pdf --black-and-white $< -o $@


# Generate python-BOM
${XMLBOM}: ${SCH}
	mkdir -p ${TMP}
	${KICAD} sch export python-bom $< -o $@


${BOM}: ${XMLBOM}
	mkdir -p ${MANUFACTURING_DIR}/assembly
	${PYTHON} ${BOM_SCRIPT}  $<  $@ > $@


# Complains about output needing to be a directory, work around this
${DRILL}: ${PCB}
	mkdir -p ${MANUFACTURING_DIR}/gerbers
	${KICAD} pcb export drill --units mm $< -o ./
	mv ${PROJECT}.drl ${DRILL}


${CENTROID}: ${PCB}
	mkdir -p ${MANUFACTURING_DIR}/assembly
	${KICAD} pcb export pos --use-drill-file-origin --side both --format csv --units mm $< -o $@


${STEP}: ${PCB}
	mkdir -p 3D
	${KICAD} pcb export step $< --drill-origin --subst-models -f -o ${STEP}


gerbers: ${PCB} run-drc
	mkdir -p ${MANUFACTURING_DIR}/gerbers
	${KICAD} pcb export gerbers --subtract-soldermask $< -o ${MANUFACTURING_DIR}/gerbers

run-drc: ${PCB}
	${PCBNEW_DO} ${PCBNEW_DO} run_drc ${PCB} ./ >> ${LOG}
${IBOM}: ${PCB}
	${IBOM_SCRIPT} $< --dnp-field DNP --group-fields "Value,Footprint" --blacklist "X1,MH*" --include-nets --normalize-field-case --no-browser --dest-dir ./ --name-format %f_%r_interactive_bom

${FABZIP}: board
	zip -r ${FABZIP} ${MANUFACTURING_DIR}
	
# Add board renders

# Add expanding BOMs

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
board: gerbers ${DRILL} ${CENTROID} ${ASSEMBLY_BOM}


