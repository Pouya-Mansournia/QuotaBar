# Command-line entry points. Everything here is plain xcodebuild; opening
# QuotaBar.xcodeproj in Xcode works just as well.

# Use the full Xcode even when xcode-select points at the Command Line Tools.
export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

DERIVED := build/DerivedData
XCODEBUILD := xcodebuild -project QuotaBar.xcodeproj -scheme QuotaBar -derivedDataPath $(DERIVED) -destination 'platform=macOS'
RELEASE_APP := $(DERIVED)/Build/Products/Release/QuotaBar.app
DEBUG_APP := $(DERIVED)/Build/Products/Debug/QuotaBar.app

# Use a stable local signing identity when exactly one is available. Ad hoc
# signatures change on every build and invalidate Keychain's "Always Allow".
# Set SIGN_IDENTITY explicitly when several identities are installed.
SIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep -Eo '[A-F0-9]{40}' | awk 'NR == 1 { first = $$0 } END { if (NR == 1) print first }')
SIGN_APP = $(if $(SIGN_IDENTITY),codesign --force --preserve-metadata=entitlements --options runtime -s "$(SIGN_IDENTITY)" $(1))

.PHONY: build release test run install screenshots icon clean

build:
	$(XCODEBUILD) -configuration Debug build

release:
	$(XCODEBUILD) -configuration Release build
	$(call SIGN_APP,$(RELEASE_APP))

test:
	$(XCODEBUILD) -configuration Debug test

run: build
	$(call SIGN_APP,$(DEBUG_APP))
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
DMG := QuotaBar-$(VERSION).dmg

.PHONY: dmg zip
dmg: release
	rm -rf build/dmg $(DMG)
	mkdir -p build/dmg
	cp -R $(RELEASE_APP) build/dmg/QuotaBar.app
	ln -s /Applications build/dmg/Applications
	hdiutil create -volname QuotaBar -srcfolder build/dmg -ov -format UDZO $(DMG)
	rm -rf build/dmg
	@echo "Created $(DMG)"

# Upload this ZIP to the same GitHub Release as the Windows installer. The
# updater requires a stable signing identity, so SIGN_IDENTITY must be set.
zip:
	@test -n "$(SIGN_IDENTITY)" || (echo "A code-signing identity is required for macOS updates" >&2; exit 1)
	$(MAKE) release SIGN_IDENTITY="$(SIGN_IDENTITY)"
	rm -f QuotaBar-macOS-$(VERSION).zip
	ditto -c -k --keepParent $(RELEASE_APP) QuotaBar-macOS-$(VERSION).zip

# Build the macOS disk image (and the updater ZIP when a signing identity is
# available) and attach them to the GitHub Release v$(VERSION).
.PHONY: publish-mac
publish-mac: dmg
	$(if $(SIGN_IDENTITY),$(MAKE) zip SIGN_IDENTITY="$(SIGN_IDENTITY)",@echo "No signing identity: skipping updater ZIP")
	gh release view v$(VERSION) >/dev/null 2>&1 || gh release create v$(VERSION) --title "QuotaBar for macOS $(VERSION)" --generate-notes
	gh release upload v$(VERSION) $(DMG) $(if $(SIGN_IDENTITY),QuotaBar-macOS-$(VERSION).zip) --clobber
