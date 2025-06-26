# Include the main Makefile relative to this one
MACROFAB_DIR = $(_OUTDIR)/macrofab
MACROFAB_GERBERS_DIR = $(MACROFAB_DIR)/gerbers
MACROFAB_ZIP = $(_OUTDIR)/${PCBBASE}_${VERSION}_macrofab.zip
MACROFAB_XYRS = $(MACROFAB_DIR)/${PCBBASE}_${VERSION}_macrofab.xyrs
KICAD_XYRS_SCRIPT=kicad_xyrs

$(MACROFAB_DIR) $(MACROFAB_GERBERS_DIR):
	mkdir -p "$@"

${MACROFAB_XYRS}: ${PCB} | $(MACROFAB_DIR)
	$(KICAD_XYRS_SCRIPT) --pcb "$<" --out "$@" --format macrofab
	sed -i '1s/^/# /' "$@"  #  Comment out the header

macrofab_release: $(MACROFAB_ZIP) | $(MACROFAB_DIR)
	@echo "$(MACROFAB_GERBERS_DIR)"

macrofab_gerbers: $(PCB) $(DRILL) | $(MACROFAB_DIR) $(MACROFAB_GERBERS_DIR)
	$(KICADCLI) pcb export gerbers --use-drill-file-origin "$<" -o $(MACROFAB_GERBERS_DIR)
	cp $(DRILL) $(MACROFAB_GERBERS_DIR)
	rm -f $(wildcard $(MACROFAB_GERBERS_DIR)/*.gbrjob)
	rm -f $(wildcard $(MACROFAB_GERBERS_DIR)/*.gbr)
	rm -f $(wildcard $(MACROFAB_GERBERS_DIR)/*Adhesive*)

${MACROFAB_ZIP}: $(MACROFAB_DIR) $(MACROFAB_XYRS) macrofab_gerbers
	zip -rj "$@" "$<"

.PHONY: macrofab_release macrofab_gerbers
