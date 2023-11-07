# Requires:
# 	+ KiAuto : https://github.com/INTI-CMNB/KiAuto
# 	+ KiCAD 7.0.0+
# 	+ InteractiveHtmlBOM : https://github.com/openscopeproject/InteractiveHtmlBom
#		+ KiKit: V 1.0.3+
#
#
#
# Tools & Tool Paths
KICAD=kicad-cli
IBOM_SCRIPT=${HOME}/tools/InteractiveHtmlBom/InteractiveHtmlBom/generate_interactive_bom.py
PYTHON="/usr/bin/python3"
KICAD_PYTHON_PATH=/usr/lib/kicad/lib/python3/dist-packages
BOM_SCRIPT="/usr/share/kicad/plugins/bom_csv_grouped_by_value.py"
PCBNEW_DO=pcbnew_do # Kiauto
KIKIT=kikit

TMP=/tmp
MANUFACTURING_DIR=fab

DRC_RESULT=drc_result.rpt

# Project Information
PROJECT=PROJECTNAME
SCH=${PROJECT}.kicad_sch
PCB=${PROJECT}.kicad_pcb
PCBBASE=$(basename ${PCB})
SCHBASE=$(basename ${SCH})
VERSION=A.B.X

PDFSCH=${SCHBASE}_${VERSION}.pdf
LOG=log.log
MECH_DIR=mechanical
XMLBOM=${TMP}/${SCHBASE}_${VERSION}_BOM.xml
BOM=${MANUFACTURING_DIR}/assembly/${SCHBASE}_${VERSION}_BOM.csv
LCSCBOM=${MANUFACTURING_DIR}/assembly/${SCHBASE}_${VERSION}_LCSC_BOM.csv

DRILL=${MANUFACTURING_DIR}/gerbers/drill.drl
STEP=${MECH_DIR}/${PCBBASE}_${VERSION}.step
CENTROID=${MANUFACTURING_DIR}/assembly/centroid.csv
JLC_CENTROID=${MANUFACTURING_DIR}/assembly/jlc-centroid.csv
IBOM=${PCBBASE}_${VERSION}_interactive_bom.html
FABZIP=${PCBBASE}_${VERSION}.zip
GENCAD=${PCBBASE}_${VERSION}.cad
OUTLINE=${MECH_DIR}/board-outline.svg


export PYTHONPATH=${KICAD_PYTHON_PATH}


.PHONY: all
all: schematic BOM ibom step drc gerbers board fabzip

.PHONY: no-drc
no-drc: schematic BOM ibom step gerbers board fabzip

clean:
	rm ${PDFSCH} ${XMLBOM} ${BOM} ${STEP} ${CENTROID} ${JLC_CENTROID} ${IBOM} ${MANUFACTURING_DIR}/gerbers/*
	rm ${FABZIP} kicad-cli ${OUTLINE}
	rmdir ${MANUFACTURING_DIR}/gerbers ${MANUFACTURING_DIR}/assembly ${MANUFACTURING_DIR}
	rmdir 3D 


drc: ${PCB}
	${KIKIT} drc run $<
	#${PCBNEW_DO} run_drc $< ./ >> log.log

erc: ${SCH}
	${PCBNEW_DO} run_erc $< ./ >> log.log

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
	${KICAD} pcb export drill --excellon-units mm $< -o ./
	mv ${PCBBASE}.drl $@


${CENTROID}: ${PCB}
	mkdir -p ${MANUFACTURING_DIR}/assembly
	${KICAD} pcb export pos --use-drill-file-origin --side both --format csv --units mm $< -o $@


${JLC_CENTROID}: ${CENTROID}
	#echo "Ref,Val,Package,PosX,PosY,Rot,Side" >> 
	echo "Designator,Comment,Footprint,Mid X,Mid Y,Rotation,Layer" > $@
	tail --lines=+2 $< >> $@


${STEP}: ${PCB}
	mkdir -p ${MECH_DIR}
	${KICAD} pcb export step $< --drill-origin --subst-models -f -o $@


gerbers: ${PCB} #drc
	mkdir -p ${MANUFACTURING_DIR}/gerbers
	${KICAD} pcb export gerbers --subtract-soldermask $< -o ${MANUFACTURING_DIR}/gerbers


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
board: gerbers ${DRILL} ${CENTROID} ${JLC_CENTROID} ${ASSEMBLY_BOM} ${OUTLINE}

.PHONY: setup
setup: ${ASSEMBLY_BOM} ${BOM} schematic ibom step
