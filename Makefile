# Discover tool paths
STYLUA := $(shell which stylua 2>/dev/null || echo "$$HOME/.cargo/bin/stylua")
LUACHECK := $(shell which luacheck 2>/dev/null || echo "$$HOME/.luarocks/bin/luacheck")

.PHONY: install lint format format-fix check all

# Install dependencies
install:
	cargo install stylua
	luarocks install --local luacheck
	@echo "Tools installed. Make sure ~/.cargo/bin and ~/.luarocks/bin are in your PATH"

# Run luacheck for linting
lint:
	@test -x $(LUACHECK) || (echo "Error: luacheck not found. Run 'make install' first." && exit 1)
	$(LUACHECK) lua/ plugin/ ftplugin/

# Run stylua for formatting
format:
	@test -x $(STYLUA) || (echo "Error: stylua not found. Run 'make install' first." && exit 1)
	$(STYLUA) --check lua/ plugin/ ftplugin/

# Format files in place
format-fix:
	@test -x $(STYLUA) || (echo "Error: stylua not found. Run 'make install' first." && exit 1)
	$(STYLUA) lua/ plugin/ ftplugin/

# Run all checks
check: lint format

# Default target
all: check
