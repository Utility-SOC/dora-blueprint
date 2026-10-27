.PHONY: init cloud-persistent cloud-up cloud-down cloud-reap lab-core lab-full lab-dr drill evidence evidence-verify test images

# Targets not yet implemented fail loudly rather than pretending to work —
# see build-spec P1 (no claim without an implementation).

# Make this clone your own instance: fresh age key, PKI, and credentials; rewrites the repo URL
# and UI host. e.g. make init REPO_URL=https://github.com/<you>/dora-blueprint.git PLATFORM_HOST=10.0.0.5
init:
	@NEW_REPO_URL="$(REPO_URL)" NEW_PLATFORM_HOST="$(PLATFORM_HOST)" bash bootstrap/init.sh

lab-core:
	@bash bootstrap/install.sh

lab-full:
	@TIER=full bash bootstrap/install.sh

# AWS (infra/aws/, docs/08-instantiation.md). cloud-persistent once per account; then
# make cloud-up ADMIN_CIDRS=203.0.113.4/32 [TTL_HOURS=4] [LAB_NAME=dora-lab] ... make cloud-down
TF ?= tofu
cloud-persistent:
	@test -n "$(BUDGET_EMAIL)" || { echo "usage: make cloud-persistent BUDGET_EMAIL=you@example.com [GITHUB_REPOSITORY=owner/repo]"; exit 1; }
	@$(TF) -chdir=infra/aws/persistent init -input=false
	@$(TF) -chdir=infra/aws/persistent apply -var budget_alert_email="$(BUDGET_EMAIL)" -var github_repository="$(GITHUB_REPOSITORY)"

cloud-up:
	@TF=$(TF) bash infra/aws/cloud.sh up

cloud-down:
	@TF=$(TF) bash infra/aws/cloud.sh down

cloud-reap:
	@TF=$(TF) bash infra/aws/cloud.sh reap

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

# No cluster needed -- also run by .github/workflows/offline-checks.yaml on every PR.
test:
	@python3 tests/test_offline.py
	@if command -v age >/dev/null && command -v sops >/dev/null; then bash tests/test_init.sh; \
	  else echo "skipping tests/test_init.sh (needs age + sops; CI runs it)"; fi

images:
	@echo "images: no local target -- built, signed (cosign keyless), and SBOM-attested by .github/workflows/build-images.yaml instead (Phase 12, done)"; exit 1
