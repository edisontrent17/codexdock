GOCACHE ?= /tmp/codexdock-gocache
GOMODCACHE ?= /tmp/codexdock-gomodcache
export GOCACHE
export GOMODCACHE

.PHONY: test build package install smoke e2e-plan e2e-preflight e2e-local e2e-remote validate-e2e-report trent-record-e2e trent-close-roadmap trent-finalize-e2e clean

test:
	GOCACHE=$(GOCACHE) GOMODCACHE=$(GOMODCACHE) go test -count=1 ./...

build:
	./scripts/build.sh

package:
	./scripts/package.sh

install:
	@test -n "$(SOURCE)" || (echo "SOURCE is required"; exit 2)
	./scripts/install.sh "$(SOURCE)"

smoke:
	./scripts/smoke-test.sh

e2e-plan:
	./scripts/e2e-remote.sh --print-plan

e2e-preflight:
	./scripts/e2e-remote.sh --preflight

e2e-local:
	./scripts/e2e-local-sim.sh

e2e-remote:
	./scripts/e2e-remote.sh

validate-e2e-report:
	@test -n "$(REPORT_DIR)" || (echo "REPORT_DIR is required"; exit 2)
	./scripts/validate-e2e-report.sh --full "$(REPORT_DIR)"

trent-record-e2e:
	@test -n "$(REPORT_DIR)" || (echo "REPORT_DIR is required"; exit 2)
	./scripts/trent-record-e2e.sh "$(REPORT_DIR)"

trent-close-roadmap:
	@test -n "$(REPORT_DIR)" || (echo "REPORT_DIR is required"; exit 2)
	./scripts/trent-close-roadmap.sh "$(REPORT_DIR)"

trent-finalize-e2e:
	@test -n "$(REPORT_DIR)" || (echo "REPORT_DIR is required"; exit 2)
	./scripts/trent-finalize-e2e.sh "$(REPORT_DIR)"

clean:
	rm -rf dist
