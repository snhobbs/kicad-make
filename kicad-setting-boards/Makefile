# Template boards for KiCad's Board Setup > Import Settings, one directory per
# entry in templates.yaml, built from ../fab-settings/. Regenerate and commit
# them after changing the settings:
#
#   make -C kicad-setting-boards
#
# Needs KiCad's pcbnew Python module, sexpdata and pyyaml.

HERE := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
ROOT := $(abspath $(HERE)/..)
PYTHON ?= python3

.PHONY: all list
all:
	$(PYTHON) $(ROOT)/scripts/fab_settings.py templates $(HERE)/templates.yaml

list:
	@$(PYTHON) $(ROOT)/scripts/fab_settings.py list
