# Binnacle. The library builds with `spago build`; the targets here are for
# the /link/anchor reference and its conformance vectors
# (conformance/LINK-ANCHOR.md).

VECTORS := conformance/vectors/link-anchor.json
PEERS_VECTORS := conformance/vectors/link-peers.json
ORIGIN_VECTORS := conformance/vectors/clock-origin.json
DIAPHUS_VECTORS := conformance/vectors/diaphus-inbound.json
ES9_VECTORS := conformance/vectors/es9-osc.json
GENERATE = node -e "import('./output/Test.Generate/index.js').then(m => m.$(1)())"

.PHONY: build test vectors check-vectors

build:
	spago build

# The reference against its declared cases, then a second implementation
# (Python, written from the declaration) against the committed vector file.
test:
	spago test
	python3 conformance/replay.py
	python3 conformance/replay_companions.py
	python3 conformance/replay_daemons.py

# Regenerate the vector file from the declared cases. Runs the test first:
# vectors are never written from a reference that disagrees with them.
vectors: test
	node -e "import('./output/Test.Generate/index.js').then(m => m.main())" > $(VECTORS).tmp
	mv $(VECTORS).tmp $(VECTORS)
	$(call GENERATE,peers) > $(PEERS_VECTORS).tmp
	mv $(PEERS_VECTORS).tmp $(PEERS_VECTORS)
	$(call GENERATE,origin) > $(ORIGIN_VECTORS).tmp
	mv $(ORIGIN_VECTORS).tmp $(ORIGIN_VECTORS)
	$(call GENERATE,diaphus) > $(DIAPHUS_VECTORS).tmp
	mv $(DIAPHUS_VECTORS).tmp $(DIAPHUS_VECTORS)
	$(call GENERATE,es9) > $(ES9_VECTORS).tmp
	mv $(ES9_VECTORS).tmp $(ES9_VECTORS)
	node conformance/tables.mjs write

# Fails if the committed vector file is not what the cases generate.
check-vectors: test
	node -e "import('./output/Test.Generate/index.js').then(m => m.main())" | diff -u $(VECTORS) -
	$(call GENERATE,peers) | diff -u $(PEERS_VECTORS) -
	$(call GENERATE,origin) | diff -u $(ORIGIN_VECTORS) -
	$(call GENERATE,diaphus) | diff -u $(DIAPHUS_VECTORS) -
	$(call GENERATE,es9) | diff -u $(ES9_VECTORS) -
	node conformance/tables.mjs check
