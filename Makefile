MAC := mac
APP := $(MAC)/.build/Omnipen.app

.PHONY: build test bundle run release clean

build:
	swift build --package-path $(MAC)

test:
	swift test --package-path $(MAC)

bundle:
	@$(MAC)/Scripts/bundle.sh debug

# A stale instance would keep its own status item around.
run: bundle
	@pkill -x Omnipen 2>/dev/null || true
	@open $(APP)
	@echo "Omnipen running. Look for the pen in the menu bar."

release:
	@$(MAC)/Scripts/bundle.sh release

clean:
	rm -rf $(MAC)/.build
