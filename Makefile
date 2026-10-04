.PHONY: lab-core lab-full lab-dr drill evidence evidence-verify images test

# Targets not yet implemented fail loudly rather than pretending to work —
# see build-spec P1 (no claim without an implementation).

lab-core:
	@bash bootstrap/install.sh

lab-full:
	@TIER=full bash bootstrap/install.sh

lab-dr:
	@echo "lab-dr: not implemented -- the full tier (make lab-full: apps/core/ + apps/full/, IAM/Tetragon/Trivy) is real; a genuine second cluster plus a cross-cluster restore drill beyond that is still unbuilt (build-spec Phase 19, README.md roadmap)"; exit 1

drill:
	@test -n "$(SCENARIO)" || { echo "usage: make drill SCENARIO=<name>"; exit 1; }
	@SCENARIO=$(SCENARIO) bash drills/lib/run-drill.sh

evidence:
	@python3 docs/evidence/collect.py
	@python3 docs/evidence/chain.py
	@python3 docs/evidence/oscal.py
	@python3 docs/evidence/report.py

evidence-verify:
	@python3 docs/evidence/chain.py --verify

images:
	@echo "images: no local target -- built, signed (cosign keyless), and SBOM-attested by .github/workflows/build-images.yaml instead (Phase 12, done)"; exit 1

test:
	@python3 -m pytest
