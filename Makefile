DEPS_DIR = .deps/start

$(DEPS_DIR)/plenary.nvim:
	git clone --depth 1 https://github.com/nvim-lua/plenary.nvim $@

_deps: $(DEPS_DIR)/plenary.nvim

test: _deps
	nvim \
	  --headless \
	  -u tests/minimal_init.lua \
	  -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }"

clean:
	rm -rf .cache .deps
