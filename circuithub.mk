CIRCUITHUB_DIR = $(_OUTDIR)/circuithub

$(CIRCUITHUB_DIR):
	mkdir -p "$@"

CIRCUITHUB_IPC2581 = $(CIRCUITHUB_DIR)/IPC2581_${PCBBASE}_${VERSION}.xml.cvg
CIRCUITHUB_BOM = $(CIRCUITHUB_DIR)/$(notdir $(BOM))

$(CIRCUITHUB_IPC2581): ${IPC2581} | $(CIRCUITHUB_DIR)
	cp $< $@

$(CIRCUITHUB_BOM): ${BOM} | $(CIRCUITHUB_DIR)
	cp $< $@

circuithub_release: $(CIRCUITHUB_IPC2581) $(CIRCUITHUB_BOM)| 
	@echo "Preparing files for CircuitHub release"
	@echo "files copied to $(CIRCUITHUB_DIR)"

.PHONY: circuithub_release
