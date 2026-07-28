.PHONY: lab-core lab-full lab-dr drill evidence images

# Phase 0: stubs only. Each target fails loudly rather than pretending to work —
# see build-spec P1 (no claim without an implementation).

lab-core:
	@echo "lab-core: not implemented yet (build-spec Phase 1)"; exit 1

lab-full:
	@echo "lab-full: not implemented yet (build-spec Phase 1/5)"; exit 1

lab-dr:
	@echo "lab-dr: not implemented yet (build-spec Phase 8+, out of Phase 3 milestone scope)"; exit 1

drill:
	@echo "drill: not implemented yet (build-spec Phase 2/3, needs SCENARIO=<name>)"; exit 1

evidence:
	@echo "evidence: not implemented yet (build-spec Phase 8)"; exit 1

images:
	@echo "images: not implemented yet (build-spec Phase 6)"; exit 1
