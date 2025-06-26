# JLCPCB currently only accepts gerbers, BOMs, and centroids
# Their field matching is poor so it is useful to generate all the files
# in the exact format they expect.

JLCPCB_DIR = $(_OUTDIR)/jlcpcb
JLCPCB_GERBERS_DIR = $(JLCPCB_DIR)/gerbers
JLCPCB_ZIP = $(_OUTDIR)/$(PCBBASE)_$(VERSION)_jlcpcb.zip
LCSCBOM=$(JLCPCB_DIR)/$(SCHBASE)_$(VERSION)_LCSC_BOM.csv
JLCPCB_CENTROID=$(JLCPCB_DIR)/jlcpcb-centroid.csv

$(JLCPCB_DIR) $(JLCPCB_GERBERS_DIR):
	mkdir -p "$@"

$(JLCPCB_CENTROID): $(CENTROID_CSV) | $(ASSEMBLY_DIR)
	#echo "Ref,Val,Package,PosX,PosY,Rot,Side" >>
	echo "Designator,Comment,Footprint,Mid X,Mid Y,Rotation,Layer" > "$@"
	tail --lines=+2 "$<" >> "$@"

$(LCSCBOM): $(SCH) | $(ASSEMBLY_DIR)
	$(KICADCLI) sch export bom "$<" --fields="Reference,Value,Footprint,LCSC,\$$(QUANTITY),\$$(DNP)" --labels="Ref Des,Value,Footprint,JLCPCB Part #,QUANTITY,DNP" --group-by="LCSC,\$$(DNP),Value,Footprint" --ref-range-delimiter="" -o "$@"

$(JLCPCB_ZIP): $(JLCPCB_DIR) $(LCSCBOM) $(JLCPCB_CENTROID) jlcpcb_gerbers
	zip -rj "$@" "$<"

jlcpcb_gerbers: $(PCB) $(DRILL) | $(JLCPCB_DIR) $(JLCPCB_GERBERS_DIR)
	$(KICADCLI) pcb export gerbers --use-drill-file-origin "$<" -o $(JLCPCB_GERBERS_DIR)
	cp $(DRILL) $(JLCPCB_GERBERS_DIR)

jlcpcb_release: $(JLCPCB_ZIP) | $(JLCPCB_DIR)
	@echo "Preparing files for JLCPCB release"
	# Add any custom JLCPCB packaging steps here, for example:
	@echo "JLCPCB files copied to $(JLCPCB_DIR)"

.PHONY: jlcpcb_release jlcpcb_gerbers
