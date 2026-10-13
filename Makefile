# Command-line entry points. Everything here is plain xcodebuild; opening
# QuotaBar.xcodeproj in Xcode works just as well.

# Use the full Xcode even when xcode-select points at the Command Line Tools.
export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

DERIVED := build/DerivedData
XCODEBUILD := xcodebuild -project QuotaBar.xcodeproj -scheme QuotaBar -derivedDataPath $(DERIVED) -destination 'platform=macOS'
RELEASE_APP := $(DERIVED)/Build/Products/Release/QuotaBar.app
DEBUG_APP := $(DERIVED)/Build/Products/Debug/QuotaBar.app

.PHONY: build release test run install screenshots icon clean

build:
	$(XCODEBUILD) -configuration Debug build

release:
	$(XCODEBUILD) -configuration Release build

test:
	$(XCODEBUILD) -configuration Debug test

run: build
	-pkill -x QuotaBar
	open $(DEBUG_APP)

# Launch at login needs the app at a stable location.
install: release
	-pkill -x QuotaBar
	rm -rf /Applications/QuotaBar.app
	cp -R $(RELEASE_APP) /Applications/QuotaBar.app
	open /Applications/QuotaBar.app

screenshots:
	TEST_RUNNER_QUOTABAR_SCREENSHOTS=1 $(XCODEBUILD) -configuration Debug -only-testing:QuotaBarTests/ScreenshotTests test

icon:
	swift Scripts/generate-icon.swift

clean:
	rm -rf build

# Disk image for sharing. Ad hoc signed and not notarized: see README.
VERSION := $(shell sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' QuotaBar.xcodeproj/project.pbxproj | head -1)
DMG := build/QuotaBar-$(VERSION).dmg

.PHONY: dmg
dmg: release
	rm -rf build/dmg $(DMG)
	mkdir -p build/dmg
	cp -R $(RELEASE_APP) build/dmg/QuotaBar.app
	ln -s /Applications build/dmg/Applications
	hdiutil create -volname QuotaBar -srcfolder build/dmg -ov -format UDZO $(DMG)
	rm -rf build/dmg
	@echo "Created $(DMG)"
