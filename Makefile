# Project Information. Call this make file with those values set
#===============================================================
PROJECT=PROJECTNAME
VERSION=A.B.X
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
# KICADCLI=kicad-cli
#	flatpak
#	KICADCLI=flatpak run --command=kicad-cli org.kicad.KiCad
#	snap
#	KICADCLI=/snap/bin/kicad.kicad-cli
#	docker
KICADCLI=docker run -v /tmp/.X11-unix:/tmp/.X11-unix -v ${HOME}:${HOME} -it --rm -e DISPLAY=:0 --name kicad-cli kicad/kicad:9.0 kicad-cli
SCH_DRAWING_SHEET={ROOT_DIR}/SchDrawingSheet.kicad_wks
PCB_DRAWING_SHEET=${SCH_DRAWING_SHEET}
IBOM_SCRIPT=generate_interactive_bom
BOARD2PDF=board2pdf
PYTHON="/usr/bin/python3"
KICAD_PYTHON_PATH=/usr/lib/kicad/lib/python3/dist-packages
#KICAD_PYTHON_PATH=/usr/lib/python3/dist-packages/_pcbnew.so
#===============================================================

_DIR=$(abspath ${DIR})
_OUTDIR=$(abspath ${OUTDIR})
MANUFACTURING_DIR=${_OUTDIR}/fab
ASSEMBLY_DIR=${MANUFACTURING_DIR}/assembly
GERBER_DIR=${MANUFACTURING_DIR}/gerbers
LOGS_DIR=${_OUTDIR}/logs
MECH_DIR=${_OUTDIR}/mechanical
GERBER_PDF_DIR=${_OUTDIR}/gerberpdf

LOG=${_DIR}/log.log
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
RENDER_TOP=${_OUTDIR}/${PCBBASE}_${VERSION}_Render_TOP.png
RENDER_BOTTOM=${_OUTDIR}/${PCBBASE}_${VERSION}_Render_BOTTOM.png

# BOMS & Assembly
CENTROID_CSV=${ASSEMBLY_DIR}/centroid.csv
CENTROID_GERBER=${ASSEMBLY_DIR}/centroid.gerber
JLC_CENTROID=${ASSEMBLY_DIR}/jlc-centroid.csv

# Manufacturing Files
DRILL=${MANUFACTURING_DIR}/gerbers/drill.drl
FABZIP=${_OUTDIR}/${PCBBASE}_${VERSION}.zip
GENCAD=${_OUTDIR}/GENCAD_${PCBBASE}_${VERSION}.cad
ODB=${_OUTDIR}/ODB_${PCBBASE}_${VERSION}.zip
IPC2581=${_OUTDIR}/IPC2581_${PCBBASE}_${VERSION}.xml

# MECHANICAL
MECH_DIR=${_OUTDIR}/mechanical
STEP=${MECH_DIR}/${PCBBASE}_${VERSION}.step
OUTLINE=${MECH_DIR}/board-outline.svg

# GerberPDF
PDF_GERBER_LAYERS := \
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
	B.Silkscreen

PDF_GERBER_LAYERS_CSV := $(subst $(SPACE),$(COMMA),$(PDF_GERBER_LAYERS))
PDF_GERBER_FILES := $(foreach f,${PDF_GERBER_LAYERS},${GERBER_PDF_DIR}/${PCBBASE}-$(subst .,_,$(f)).pdf)

.PHONY: release
release: erc drc manufacturing fabzip

.PHONY: manufacturing
manufacturing: ${GERBER_PDF_DIR} ${GERBER_DIR} ${MECH_DIR} ${ASSEMBLY_DIR} renders schematic boms gerberpdf ibom step gerbers board ipc2581 odb gencad

.PHONY: no-drc
no-drc: manufacturing fabzip 

.PHONY: clean
clean:
	-rm ${PDF_GERBER_FILES}
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
	-rm ${RENDER_TOP} ${RENDER_BOTTOM}
	-rm ${GERBER_PDF_DIR}/*.pdf
	-rm ${GENCAD}
	-rm ${ODB}
	-rm ${IPC2581}
	-rm -r ${GERBER_DIR}
	-rmdir ${MECH_DIR}
	-rmdir ${GERBER_DIR} ${ASSEMBLY_DIR} ${MANUFACTURING_DIR} ${GERBER_PDF_DIR} ${LOGS_DIR}


#.PHONY: ${DRC}
${DRC}: ${PCB} ${ERC} | ${LOGS_DIR}
	${KICADCLI} pcb drc --exit-code-violations $< -o ${LOGS_DIR}/drc-out.log
	mv ${LOGS_DIR}/drc-out.log $@

#.PHONY: ${ERC}
${ERC}: ${SCH} | ${LOGS_DIR}	
	${KICADCLI} sch erc --exit-code-violations $< -o ${LOGS_DIR}/erc-out.log
	mv ${LOGS_DIR}/erc-out.log $@

SCHEMATIC_FLAGS=--black-and-white --drawing-sheet ${SCH_DRAWING_SHEET}
# Generates schematic
${PDFSCH} : ${SCH} | ${_OUTDIR}
	${KICADCLI} sch export pdf ${SCHEMATIC_FLAGS} $< -o $@

${BOM}: ${SCH} | ${ASSEMBLY_DIR}
	${KICADCLI} sch export bom $< --fields "Reference,Value,Footprint,\$${QUANTITY},\$${DNP},MPN,LCSC,Notes" --group-by="\$${DNP},Value,Footprint" --ref-range-delimiter="" -o $@

${LCSCBOM}: ${SCH} | ${ASSEMBLY_DIR}
	${KICADCLI} sch export bom $< --fields="Reference,Value,Footprint,LCSC,\$${QUANTITY},\$${DNP}" --labels="Ref Des,Value,Footprint,JLCPCB Part #,QUANTITY,DNP" --group-by="LCSC,\$${DNP},Value,Footprint" --ref-range-delimiter="" -o $@

${LOGS_DIR}: ${_OUTDIR}
	mkdir -p $@

${MANUFACTURING_DIR}:
	mkdir -p $@

${ASSEMBLY_DIR}: | ${MANUFACTURING_DIR}
	mkdir -p $@

${GERBER_DIR}: | ${MANUFACTURING_DIR}
	mkdir -p $@

${MECH_DIR}: | ${MANUFACTURING_DIR}
	mkdir -p $@

${GERBER_PDF_DIR}: | ${MANUFACTURING_DIR}
	mkdir -p $@

# Complains about output needing to be a directory, work around this
${DRILL}: ${PCB} | ${GERBER_DIR}
	${KICADCLI} pcb export drill --drill-origin plot --excellon-units mm $< -o ${GERBER_DIR}
	mv ${GERBER_DIR}/${PCBBASE}.drl $@

${CENTROID_CSV}: ${PCB} | ${ASSEMBLY_DIR}
	${KICADCLI} pcb export pos --use-drill-file-origin --side both --format csv --units mm $< -o $@

${JLC_CENTROID}: ${CENTROID_CSV} | ${ASSEMBLY_DIR}
	#echo "Ref,Val,Package,PosX,PosY,Rot,Side" >>
	echo "Designator,Comment,Footprint,Mid X,Mid Y,Rotation,Layer" > $@
	tail --lines=+2 $< >> $@

${STEP}: ${PCB} | ${MECH_DIR}
	${KICADCLI} pcb export step $< --drill-origin --subst-models -f -o $@

.PHONY: gerbers
gerbers: ${PCB} | ${GERBER_DIR}
	${KICADCLI} pcb export gerbers --use-drill-file-origin $< -o ${GERBER_DIR}

# Screen size required for running headless
# https://github.com/openscopeproject/InteractiveHtmlBom/wiki/Tips-and-Tricks
# NOTE: The version in this file is taken from the PCB title block and may not match
# the delared version. These need to be adjusted manually.
${IBOM}: ${PCB} | ${ASSEMBLY_DIR}
	xvfb-run --auto-servernum --server-args "-screen 0 1024x768x24" ${IBOM_SCRIPT} $< --dnp-field DNP --group-fields "Value,Footprint" --blacklist "X1,MH*" --include-nets --normalize-field-case --no-browser --dest-dir ./ --name-format $(basename $@ .html)

${FABZIP}: ${GERBER_DIR}
	zip -rj $@ $<

${OUTLINE}: ${PCB} | ${MECH_DIR}
	${KICADCLI} pcb export svg -l "Edge.Cuts" --black-and-white --exclude-drawing-sheet $< -o $@

${GERBERPDF}: ${PCB} | ${GERBER_PDF_DIR}
	${KICADCLI} pcb export pdf ${PCB} --black-and-white --cl "Edge.Cuts" -l ${PDF_GERBER_LAYERS_CSV} -o ${GERBER_PDF_DIR} \
		--drawing-sheet ${PCB_DRAWING_SHEET} \
		--mode-separate --include-border-title --sketch-pads-on-fab-layers

# Filter out the layers that don't exist
# pdfunite $(shell for f in $(PDF_GERBER_FILES); do [ -e "$$f" ] && printf "%s " "$$f"; done) $@
	@existing_files=$$(for f in $(PDF_GERBER_FILES); do \
		[ -e "$$f" ] && printf "%s " "$$f"; done);\
		if [ -n "$$existing_files" ]; then \
			pdfunite  $$existing_files $@; \
			else \
			echo "No PDFS to merge"; \
			touch $@; \
	  fi

${RENDER_BOTTOM}: ${PCB} | ${_OUTPUT_DIR}
	${KICADCLI} pcb render --side bottom --background transparent --quality high $< -o $@

${RENDER_TOP}: ${PCB} | ${_OUTPUT_DIR}
	${KICADCLI} pcb render --side top --background transparent --quality high $< -o $@

${IPC2581}: ${PCB} | ${_OUTPUT_DIR}
	${KICADCLI} pcb export ipc2581 $< -o $@

${GENCAD}: ${PCB} | ${_OUTPUT_DIR}
	${KICADCLI} pcb export gencad $< -o $@

${ODB}: ${PCB} | ${_OUTPUT_DIR}
	${KICADCLI} pcb export odb $< -o $@

.PHONY: odb
odb: ${ODB}

.PHONY: gencad
gencad: ${GENCAD}

.PHONY: ipc2581
ipc2581: ${IPC2581}

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

.PHONY: boms
boms: ${ASSEMBLY_DIR} ${BOM} ${LCSCBOM} ${ASSEMBLY_BOM} ibom

.PHONY: XMLBOM
XMLBOM: ${XMLBOM}

.PHONY: board
board: gerbers ${DRILL} ${CENTROID_CSV} ${JLC_CENTROID} boms ${OUTLINE}

.PHONY: setup
setup: boms schematic ibom step

.PHONY: gerberpdf
gerberpdf: ${GERBERPDF}

.PHONY: centroid
centroid: ${CENTROID} ${JLC_CENTROID}

.PHONY: renders
renders: ${RENDER_TOP} ${RENDER_BOTTOM}
