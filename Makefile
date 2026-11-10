# Binnacle. The library builds with `spago build`; the targets here are for
# the /link/anchor reference and its conformance vectors
# (conformance/LINK-ANCHOR.md).

VECTORS := conformance/vectors/link-anchor.json

.PHONY: build test vectors check-vectors

build:
	spago build

# The reference against its declared cases, then a second implementation
# (Python, written from the declaration) against the committed vector file.
test:
	spago test
	python3 conformance/replay.py

# Regenerate the vector file from the declared cases. Runs the test first:
# vectors are never written from a reference that disagrees with them.
vectors: test
	node -e "import('./output/Test.Generate/index.js').then(m => m.main())" > $(VECTORS).tmp
	mv $(VECTORS).tmp $(VECTORS)

# Fails if the committed vector file is not what the cases generate.
check-vectors: test
	node -e "import('./output/Test.Generate/index.js').then(m => m.main())" | diff -u $(VECTORS) -
