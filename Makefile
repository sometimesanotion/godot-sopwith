.PHONY: all help init build run clean test format export

GODOT ?= godot
EXPORT_PRESET ?= Linux
PROJECT_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))

all: help

help:
	@echo "Godot Sopwith - Build Targets"
	@echo "=============================="
	@echo "init       - Initialize Godot project (generate .godot folder)"
	@echo "build      - Run Godot in headless mode to compile scripts"
	@echo "run        - Run the game"
	@echo "clean      - Clean generated files"
	@echo "test       - Run editor tests"
	@echo "format     - Format GDScript files"
	@echo "export     - Export game (requires export templates)"
	@echo ""
	@echo "Environment Variables:"
	@echo "  GODOT        - Path to Godot binary (default: godot)"
	@echo "  EXPORT_PRESET - Export preset name (default: Linux)"

init:
	$(GODOT) --headless --editor --quit-after 10 $(PROJECT_DIR)

build:
	$(GODOT) --headless --script-check $(PROJECT_DIR)

run:
	$(GODOT) $(PROJECT_DIR)

clean:
	rm -rf $(PROJECT_DIR)/.godot
	rm -rf $(PROJECT_DIR)/export_presets.cfg

test:
	$(GODOT) --headless --test $(PROJECT_DIR)

format:
	find $(PROJECT_DIR) -name "*.gd" -exec gdformat {} \;

export:
	$(GODOT) --headless --export-release "$(EXPORT_PRESET)" "$(PROJECT_DIR)/bin/sopwith" $(PROJECT_DIR)

verify-headers:
	@echo "Verifying Godot 4.x installation..."
	$(GODOT) --version | head -1

setup: verify-headers init