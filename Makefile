.DEFAULT_GOAL := help

# The bundle and its executable carry the product name, spaces and all. The
# Xcode project, target and scheme keep the space-free one, and so does the
# published archive: that name ends up in a download URL.
APP_NAME      := Write Less
PROJECT_NAME  := Writeless
ARCHIVE_NAME  := Writeless
BUNDLE_ID     := dev.romus.writeless
PROJECT       := $(PROJECT_NAME).xcodeproj
SCHEME        := $(PROJECT_NAME)
BUILD_DIR     := build
DERIVED       := $(BUILD_DIR)/dd
DIST_DIR      := $(BUILD_DIR)/dist
SPM_CACHE     := .spm
VERSION       := $(shell sed -n 's/^MARKETING_VERSION = //p' Config/Version.xcconfig)
CORE          := Packages/WritelessCore

# Release signing. "-" is ad-hoc; pass a certificate name to use a real
# identity, e.g. make release SIGN_IDENTITY="Developer ID Application: …".
SIGN_IDENTITY ?= -

# Icon variant from the design: graphite, paper or blue.
SKIN ?= graphite

XCB := xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
	-destination 'generic/platform=macOS' \
	-derivedDataPath $(DERIVED) -clonedSourcePackagesDirPath $(SPM_CACHE) \
	-onlyUsePackageVersionsFromResolvedFile

.PHONY: help setup-signing icon project build run test release zip cask install uninstall version clean

help: ## Show available commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

setup-signing: ## Sign Debug builds with your Apple Development certificate
	@./scripts/setup_local_signing.sh

icon: ## Re-render the app icon (SKIN=graphite|paper|blue)
	@swift scripts/make_appicon.swift --skin $(SKIN)

project: ## Regenerate Writeless.xcodeproj from project.yml
	@command -v xcodegen >/dev/null || { echo "xcodegen missing: brew install xcodegen" >&2; exit 1; }
	@xcodegen generate

build: ## Build the Debug app
	@$(XCB) -configuration Debug build

run: build ## Build and launch the Debug app
	@pkill -x "$(APP_NAME)" 2>/dev/null || true
	@open "$(DERIVED)/Build/Products/Debug/$(APP_NAME).app"

test: ## Run the WritelessCore tests
	@swift test --package-path $(CORE)

release: ## Build a signed release app (SIGN_IDENTITY=- is ad-hoc)
	@echo "==> Building $(APP_NAME) $(VERSION) (identity: $(SIGN_IDENTITY))"
	@rm -rf "$(DIST_DIR)"
	@mkdir -p "$(DIST_DIR)"
	@$(XCB) -configuration Release \
		CODE_SIGN_IDENTITY="$(SIGN_IDENTITY)" \
		$(if $(filter-out -,$(SIGN_IDENTITY)),OTHER_CODE_SIGN_FLAGS=--timestamp,) \
		build
	@ditto "$(DERIVED)/Build/Products/Release/$(APP_NAME).app" "$(DIST_DIR)/$(APP_NAME).app"
	@codesign --verify --strict --verbose=2 "$(DIST_DIR)/$(APP_NAME).app"
	@echo "==> $(DIST_DIR)/$(APP_NAME).app is ready"

zip: release ## Build the release app and archive it for Homebrew
	@cd "$(DIST_DIR)" && ditto -c -k --keepParent "$(APP_NAME).app" "$(ARCHIVE_NAME)-$(VERSION).zip"
	@echo "==> SHA256: $$(shasum -a 256 "$(DIST_DIR)/$(ARCHIVE_NAME)-$(VERSION).zip" | awk '{print $$1}')"

cask: ## Render the Homebrew cask for the built archive
	@./scripts/render_cask.sh \
		--version "$(VERSION)" \
		--sha256 "$$(shasum -a 256 '$(DIST_DIR)/$(ARCHIVE_NAME)-$(VERSION).zip' | awk '{print $$1}')" \
		--output "$(DIST_DIR)/writeless.rb"
	@echo "==> $(DIST_DIR)/writeless.rb"

install: release ## Install the release build into /Applications
	@if command -v brew >/dev/null 2>&1 && brew list --cask writeless >/dev/null 2>&1; then \
		echo "!! the writeless cask also manages /Applications/$(APP_NAME).app" >&2; \
		echo "!! installing anyway; brew upgrade --cask writeless will overwrite this build" >&2; \
	fi
	@if [ -d "/Applications/$(APP_NAME).app" ] && \
	   [ "$$(defaults read "/Applications/$(APP_NAME).app/Contents/Info" CFBundleIdentifier 2>/dev/null)" != "$(BUNDLE_ID)" ]; then \
		echo "!! replacing a different app already at /Applications/$(APP_NAME).app" >&2; \
	fi
	@pkill -x "$(APP_NAME)" 2>/dev/null || true
	@rm -rf "/Applications/$(APP_NAME).app"
	@ditto "$(DIST_DIR)/$(APP_NAME).app" "/Applications/$(APP_NAME).app"
	@echo "==> Installed /Applications/$(APP_NAME).app"

uninstall: ## Remove the app from /Applications (settings and models are kept)
	@if command -v brew >/dev/null 2>&1 && brew list --cask writeless >/dev/null 2>&1; then \
		echo "!! the writeless cask manages this app; brew uninstall --cask writeless is the tidy way" >&2; \
	fi
	@if [ ! -d "/Applications/$(APP_NAME).app" ]; then \
		echo "==> nothing installed at /Applications/$(APP_NAME).app"; \
	elif [ "$$(defaults read "/Applications/$(APP_NAME).app/Contents/Info" CFBundleIdentifier 2>/dev/null)" != "$(BUNDLE_ID)" ]; then \
		echo "!! /Applications/$(APP_NAME).app is not $(BUNDLE_ID); leaving it alone" >&2; \
		exit 1; \
	else \
		pkill -x "$(APP_NAME)" 2>/dev/null || true; \
		rm -rf "/Applications/$(APP_NAME).app"; \
		echo "==> Removed /Applications/$(APP_NAME).app"; \
		echo "    kept: ~/Library/Application Support/Writeless (models), ~/Library/Preferences/$(BUNDLE_ID).plist"; \
	fi

version: ## Print the app version
	@echo "$(VERSION)"

clean: ## Remove build output
	@rm -rf "$(BUILD_DIR)"
	@swift package --package-path $(CORE) clean 2>/dev/null || true
