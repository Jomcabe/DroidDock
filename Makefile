# DroidDock — developer convenience wrapper around the XcodeGen + xcodebuild flow.
SHELL    := /bin/bash
APP_NAME := DroidDock
SCHEME   := DroidDock
CONFIG   ?= Debug
DERIVED  := build
PROJECT  := $(APP_NAME).xcodeproj
PRODUCT  := $(DERIVED)/Build/Products/$(CONFIG)/$(APP_NAME).app
APP_INSTALL_DIR ?= /Applications

.PHONY: all setup generate build run open install sign clean reset help

## all: fetch binaries, generate the project, and build (default)
all: setup generate build

## setup: download + ad-hoc-sign the embedded adb & scrcpy toolchain
setup:
	@scripts/fetch-binaries.sh

## generate: (re)generate DroidDock.xcodeproj from project.yml
generate:
	@command -v xcodegen >/dev/null 2>&1 || { \
		echo "✗ XcodeGen not found — install it with:  brew install xcodegen"; exit 1; }
	@xcodegen generate
	@echo "✓ generated $(PROJECT)"

## build: compile the app (Debug by default; CONFIG=Release for release)
build: generate
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) build

## run: build then launch DroidDock.app
run: build
	@open "$(PRODUCT)"

## open: open the project in Xcode (⌘R to run)
open: generate
	@xed $(PROJECT)

## install: build (Release) and copy DroidDock.app into /Applications
install:
	@$(MAKE) build CONFIG=Release
	@dest="$(APP_INSTALL_DIR)"; \
	if [ ! -w "$$dest" ]; then \
		echo "⚠ $$dest not writable — installing to ~/Applications"; \
		dest="$$HOME/Applications"; mkdir -p "$$dest"; \
	fi; \
	rm -rf "$$dest/$(APP_NAME).app"; \
	cp -R "$(DERIVED)/Build/Products/Release/$(APP_NAME).app" "$$dest/"; \
	xattr -dr com.apple.quarantine "$$dest/$(APP_NAME).app" 2>/dev/null || true; \
	echo "✓ Installed → $$dest/$(APP_NAME).app"

## sign: Developer-ID sign the built app for distribution (set IDENTITY=...)
sign:
	@IDENTITY="$(IDENTITY)" scripts/codesign-app.sh "$(PRODUCT)"

## clean: remove build artifacts
clean:
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean >/dev/null 2>&1 || true
	@rm -rf $(DERIVED)
	@echo "✓ cleaned build artifacts"

## reset: clean + drop the generated project and fetched binaries
reset: clean
	@rm -rf $(PROJECT) .cache
	@rm -rf DroidDock/Resources/vendor/scrcpy DroidDock/Resources/vendor/adb \
		DroidDock/Resources/vendor/.provisioned
	@echo "✓ reset to a pristine checkout"

## help: list targets
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## //'
