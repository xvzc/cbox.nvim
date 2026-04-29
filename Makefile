DOCS_DIR ?= doc
DEPS_DIR = .deps/start

$(DEPS_DIR)/plenary.nvim:
	git clone --depth 1 https://github.com/nvim-lua/plenary.nvim $@

_deps: $(DEPS_DIR)/plenary.nvim

test: _deps
	nvim \
	  --headless \
	  -u tests/minimal_init.lua \
	  -c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/minimal_init.lua' }"

_gen-docs:
	mkdir -p $(DOCS_DIR)
	lemmy-help -f -t \
		lua/cbox/init.lua \
		lua/cbox/api.lua \
		lua/cbox/vline_block.lua \
		lua/cbox/render.lua \
		lua/cbox/comment.lua \
		lua/cbox/detect.lua \
		lua/cbox/snapshot.lua \
		> $(DOCS_DIR)/cbox.nvim.txt

docs:
	$(MAKE) _gen-docs DOCS_DIR=doc
	nvim --headless -c "helptags doc/" -c "q"

check-docs:
	mkdir -p .cache/doc/expected .cache/doc/actual
	cp doc/cbox.nvim.txt .cache/doc/expected/cbox.nvim.txt
	$(MAKE) _gen-docs DOCS_DIR=.cache/doc/actual
	diff .cache/doc/expected .cache/doc/actual

clean:
	rm -rf .cache .deps
