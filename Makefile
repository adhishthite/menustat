# MenuStat — developer workflow
# Run `make help` to see all targets.

APP_NAME       := MenuStat
SWIFT          := swift
SCRIPT         := ./script/build_and_run.sh
PACKAGE_SCRIPT := ./script/package_release.sh
RELEASE_BIN    := .build/release/$(APP_NAME)
DEBUG_BIN      := .build/debug/$(APP_NAME)
SWIFTLINT      := $(shell command -v swiftlint 2>/dev/null)
SWIFTFORMAT    := $(shell command -v swiftformat 2>/dev/null)
BREW           := $(shell command -v brew 2>/dev/null)

# Treat warnings as errors during strict CI-style builds.
STRICT_FLAGS   := -Xswiftc -warnings-as-errors

.DEFAULT_GOAL  := help

## ---------------------------------------------------------------------------
## Help
## ---------------------------------------------------------------------------

.PHONY: help
help: ## Show this help
	@awk 'BEGIN { FS = ":.*?## "; printf "\nUsage: make \033[36m<target>\033[0m\n\nTargets:\n" } \
	     /^[a-zA-Z0-9_.-]+:.*?## / { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo

## ---------------------------------------------------------------------------
## Build / Run
## ---------------------------------------------------------------------------

.PHONY: build
build: ## Debug build
	$(SWIFT) build

.PHONY: release
release: ## Optimized release build
	$(SWIFT) build -c release

.PHONY: package-release
package-release: ## Build, Developer ID sign, and zip a distributable .app
	$(PACKAGE_SCRIPT)

.PHONY: strict
strict: ## Release build with -warnings-as-errors (Swift's "type checker" gate)
	$(SWIFT) build -c release $(STRICT_FLAGS)

.PHONY: run
run: ## Build, bundle, and launch the .app
	$(SCRIPT) run

.PHONY: debug
debug: ## Launch under lldb
	$(SCRIPT) debug

.PHONY: logs
logs: ## Launch and stream os_log output
	$(SCRIPT) logs

.PHONY: verify
verify: ## Launch and assert the app is alive
	$(SCRIPT) verify

## ---------------------------------------------------------------------------
## Quality
## ---------------------------------------------------------------------------

.PHONY: lint
lint: require-swiftlint ## Run SwiftLint
	swiftlint lint --quiet --strict

.PHONY: lint-fix
lint-fix: require-swiftlint ## Apply SwiftLint autocorrections
	swiftlint --fix --quiet
	swiftlint lint --quiet

.PHONY: format
format: require-swiftformat ## Format sources in place
	swiftformat Sources

.PHONY: format-check
format-check: require-swiftformat ## Verify sources are formatted (no writes)
	swiftformat --lint Sources

.PHONY: typecheck
typecheck: ## Type-check only (no codegen/link) — Swift's nearest mypy/tsc equivalent
	$(SWIFT) build -Xswiftc -typecheck $(STRICT_FLAGS) 2>/dev/null || \
	$(SWIFT) build $(STRICT_FLAGS)

.PHONY: check
check: format-check lint strict test ## Full quality gate: format + lint + strict build + tests

.PHONY: fix
fix: format lint-fix ## Auto-fix everything that's auto-fixable

## ---------------------------------------------------------------------------
## Test
## ---------------------------------------------------------------------------

.PHONY: test
test: ## Run unit tests
	$(SWIFT) test --parallel

.PHONY: test-verbose
test-verbose: ## Run unit tests with full xctest output
	$(SWIFT) test

## ---------------------------------------------------------------------------
## Housekeeping
## ---------------------------------------------------------------------------

.PHONY: clean
clean: ## Remove build artifacts
	$(SWIFT) package clean
	rm -rf .build .swiftpm DerivedData
	rm -rf $(APP_NAME).app/Contents/MacOS

.PHONY: kill
kill: ## Kill any running $(APP_NAME) process
	-pkill -x $(APP_NAME) 2>/dev/null || true

## ---------------------------------------------------------------------------
## Tooling install
## ---------------------------------------------------------------------------

.PHONY: install-hooks
install-hooks: ## Install the git pre-commit hook
	@mkdir -p .git/hooks
	@ln -sf ../../script/pre-commit .git/hooks/pre-commit
	@chmod +x script/pre-commit
	@echo "✓ pre-commit hook linked to script/pre-commit"

.PHONY: uninstall-hooks
uninstall-hooks: ## Remove the git pre-commit hook
	@rm -f .git/hooks/pre-commit
	@echo "✓ pre-commit hook removed"

.PHONY: install-tools
install-tools: ## Install SwiftLint + SwiftFormat via Homebrew
ifndef BREW
	@echo "Homebrew not found. Install from https://brew.sh first." >&2
	@exit 1
endif
	brew list swiftlint >/dev/null 2>&1 || brew install swiftlint
	brew list swiftformat >/dev/null 2>&1 || brew install swiftformat
	@echo "✓ Tools installed."

.PHONY: require-swiftlint
require-swiftlint:
ifndef SWIFTLINT
	@echo "swiftlint not installed. Run: make install-tools" >&2
	@exit 1
endif

.PHONY: require-swiftformat
require-swiftformat:
ifndef SWIFTFORMAT
	@echo "swiftformat not installed. Run: make install-tools" >&2
	@exit 1
endif
