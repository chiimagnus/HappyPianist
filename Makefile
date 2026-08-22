# HappyPianistAVP visionOS build/test/development helpers.
# Uses Xcode's default DerivedData location so CLI and Xcode share build products.
# Defaults are copied from config.yaml and can be overridden on the command line.

SHELL := /bin/bash
.DEFAULT_GOAL := help
.NOTPARALLEL:

PROJECT ?= HappyPianist.xcodeproj
SCHEME ?= HappyPianistAVP
APP_NAME ?= HappyPianistAVP
BUNDLE_ID ?= com.chiimagnus.HappyPianistAVP
CONFIGURATION ?= Debug
MAC_SCHEME ?= HappyPianistMac
MAC_DESTINATION ?= platform=macOS,arch=arm64
MAC_ONLY_TESTING ?=

SIMULATOR_ID ?= 00CB80CD-6875-4CBB-BA94-63A58C2728EC
SIMULATOR_NAME ?= Apple Vision Pro
DEVICE_ID ?= A687F5B3-44BC-5C55-B5C4-22A807A27C6F
SIMULATOR_BOOT_TIMEOUT_SECONDS ?= 180
DESTINATION_TIMEOUT_SECONDS ?= 60
TEST_EXECUTION_TIMEOUT_SECONDS ?= 120
TEST_MAXIMUM_EXECUTION_TIMEOUT_SECONDS ?= 300
TEST_RUN_TIMEOUT_SECONDS ?= 900

XCODE_DEVELOPER_DIR ?= $(shell xcode-select -p 2>/dev/null)
XCODE_CONTENTS_DIR ?= $(patsubst %/Developer,%,$(XCODE_DEVELOPER_DIR))
DEVICE_HUB_APP ?= $(XCODE_CONTENTS_DIR)/Applications/DeviceHub.app
SIMULATOR_APP ?= $(XCODE_DEVELOPER_DIR)/Applications/Simulator.app
SIMULATOR_HOST_APP ?= $(firstword $(wildcard $(DEVICE_HUB_APP) $(SIMULATOR_APP)))

# Test reports remain repository-local. Build products use Xcode's default:
# ~/Library/Developer/Xcode/DerivedData/<project>-<hash>/
RESULT_BUNDLE_DIR ?= .build/TestResults
SIMULATOR_RESULT_BUNDLE ?= $(RESULT_BUNDLE_DIR)/HappyPianistAVP-Simulator.xcresult
DEVICE_RESULT_BUNDLE ?= $(RESULT_BUNDLE_DIR)/HappyPianistAVP-Device.xcresult
MAC_RESULT_BUNDLE ?= $(RESULT_BUNDLE_DIR)/HappyPianistMac.xcresult

define remove_result_bundle
	@attempt=0; while [ $$attempt -lt 5 ]; do \
		rtk rm -rf -- "$(1)" 2>/dev/null || true; \
		test ! -e "$(1)" && exit 0; \
		attempt=$$((attempt + 1)); \
		rtk sleep 1; \
	done; \
	echo "error: could not remove stale result bundle $(1)" >&2; \
	exit 1
endef

PARALLEL_TESTING ?= NO
ONLY_TESTING ?=
# Optional: install with `brew install xcbeautify` for compact xcodebuild output.
# ponytail: raw xcodebuild remains the fallback so the Makefile has no new dependency.
XCBEAUTIFY ?= $(shell command -v xcbeautify 2>/dev/null)
XCODEBUILD_OUTPUT ?= $(if $(strip $(XCBEAUTIFY)),2>&1 | $(XCBEAUTIFY),)
XCODEBUILD_FLAGS ?=
DEVICE_XCODEBUILD_FLAGS ?= -allowProvisioningUpdates

# Keep development output focused on app-owned structured diagnostics.
# Override these on the command line when deeper simulator logging is needed.
LOG_STYLE ?= compact
LOG_LEVEL ?= info
LOG_PREDICATE ?= subsystem == "$(BUNDLE_ID)"

SIMULATOR_DESTINATION = platform=visionOS Simulator,id=$(SIMULATOR_ID)
DEVICE_DESTINATION = platform=visionOS,id=$(DEVICE_ID)
TEST_SELECTION = $(if $(strip $(ONLY_TESTING)),-only-testing:$(ONLY_TESTING),)
MAC_TEST_SELECTION = $(if $(strip $(MAC_ONLY_TESTING)),-only-testing:$(MAC_ONLY_TESTING),)

# Deliberately omit -derivedDataPath. This makes xcodebuild use the same default
# DerivedData tree as Xcode for this project path.
XCODEBUILD_COMMON = \
	-project "$(PROJECT)" \
	-scheme "$(SCHEME)" \
	-configuration "$(CONFIGURATION)"

MAC_XCODEBUILD_COMMON = \
	-project "$(PROJECT)" \
	-scheme "$(MAC_SCHEME)" \
	-configuration "$(CONFIGURATION)"

.PHONY: help doctor config destinations clean build test dev
.PHONY: build\:mac test\:mac
.PHONY: list\:simulator open\:simulator boot\:simulator shutdown\:simulator
.PHONY: build\:simulator test\:simulator install\:simulator launch\:simulator
.PHONY: run\:simulator terminate\:simulator logs\:simulator
.PHONY: list\:device build\:device test\:device install\:device
.PHONY: launch\:device run\:device console\:device

help: ## Show available commands.
	@printf '%s\n' \
		'HappyPianistAVP visionOS Make targets' \
		'' \
		'Development shortcuts:' \
		'  make build                  Build for the configured Simulator' \
		'  make test                   Run all tests on the configured Simulator' \
		'  make build:mac              Build the isolated macOS host' \
		'  make test:mac               Run isolated macOS host tests' \
		'  make dev                    Build, install, launch, then stream app logs only' \
		'  make clean                  Clean AVP and macOS schemes and local reports' \
		'' \
		'Simulator:' \
		'  make build:simulator' \
		'  make test:simulator' \
		'  make run:simulator' \
		'  make logs:simulator' \
		'  make shutdown:simulator' \
		'' \
		'Device:' \
		'  make build:device' \
		'  make test:device' \
		'  make run:device' \
		'  make console:device         Launch and attach stdout/stderr' \
		'' \
		'Discovery:' \
		'  make destinations           Show AVP and macOS destinations' \
		'  make list:simulator' \
		'  make list:device' \
		'  make config' \
		'' \
		'DerivedData:' \
		'  Uses Xcode default: ~/Library/Developer/Xcode/DerivedData/' \
		'  No -derivedDataPath override is passed to xcodebuild.' \
		'' \
		'Overrides:' \
		'  make test:simulator SIMULATOR_ID=<udid>' \
		'  make run:device DEVICE_ID=<udid>' \
		'  make test:simulator ONLY_TESTING=HappyPianistAVPTests/GrandStaffNotationVisualTests' \
		'  make build:device CONFIGURATION=Release' \
		'  make test:mac MAC_ONLY_TESTING=HappyPianistMacTests/MacPracticeViewModelTests' \
		'  make dev LOG_LEVEL=debug    Include app debug diagnostics' \
		'  make build XCODEBUILD_FLAGS=-quiet  Use compact xcodebuild output' \
		'  brew install xcbeautify      Format xcodebuild output when available'

build: ## Build for the configured Vision Pro Simulator.
	@$(MAKE) --no-print-directory -f "$(firstword $(MAKEFILE_LIST))" 'build:simulator'

test: ## Run all tests on the configured Vision Pro Simulator.
	@$(MAKE) --no-print-directory -f "$(firstword $(MAKEFILE_LIST))" 'test:simulator'

build\:mac: doctor ## Build HappyPianistMac without a Simulator.
	@set -o pipefail; xcodebuild $(MAC_XCODEBUILD_COMMON) \
		-destination '$(MAC_DESTINATION)' \
		CODE_SIGNING_ALLOWED=NO \
		$(XCODEBUILD_FLAGS) \
		build $(XCODEBUILD_OUTPUT)
	@echo 'build:mac: BUILD SUCCEEDED'

test\:mac: doctor ## Run HappyPianistMac tests without a Simulator.
	@mkdir -p "$(RESULT_BUNDLE_DIR)"
	$(call remove_result_bundle,$(MAC_RESULT_BUNDLE))
	@set -o pipefail; xcodebuild $(MAC_XCODEBUILD_COMMON) \
		-destination '$(MAC_DESTINATION)' \
		-destination-timeout "$(DESTINATION_TIMEOUT_SECONDS)" \
		CODE_SIGNING_ALLOWED=NO \
		-parallel-testing-enabled "$(PARALLEL_TESTING)" \
		-test-timeouts-enabled YES \
		-default-test-execution-time-allowance "$(TEST_EXECUTION_TIMEOUT_SECONDS)" \
		-maximum-test-execution-time-allowance "$(TEST_MAXIMUM_EXECUTION_TIMEOUT_SECONDS)" \
		-resultBundlePath "$(MAC_RESULT_BUNDLE)" \
		$(MAC_TEST_SELECTION) \
		$(XCODEBUILD_FLAGS) \
		test $(XCODEBUILD_OUTPUT)
	@echo 'test:mac: TEST SUCCEEDED'

dev: ## Build, install, launch, then stream Simulator logs.
	@$(MAKE) --no-print-directory -f "$(firstword $(MAKEFILE_LIST))" 'open:simulator'
	@$(MAKE) --no-print-directory -f "$(firstword $(MAKEFILE_LIST))" 'run:simulator'
	@$(MAKE) --no-print-directory -f "$(firstword $(MAKEFILE_LIST))" 'logs:simulator'

doctor: ## Verify the required Apple command-line tools and project are present.
	@command -v xcodebuild >/dev/null || { echo 'error: xcodebuild not found'; exit 1; }
	@command -v xcrun >/dev/null || { echo 'error: xcrun not found'; exit 1; }
	@command -v xcode-select >/dev/null || { echo 'error: xcode-select not found'; exit 1; }
	@test -n "$(XCODE_DEVELOPER_DIR)" || { echo 'error: no active Xcode developer directory; run sudo xcode-select -s /Applications/Xcode.app/Contents/Developer'; exit 1; }
	@test -d "$(PROJECT)" || { echo 'error: project not found: $(PROJECT)'; exit 1; }
	@xcodebuild -version
	@echo 'doctor: OK'

config: ## Print the resolved Make configuration.
	@printf '%-26s %s\n' \
		'PROJECT' '$(PROJECT)' \
		'SCHEME' '$(SCHEME)' \
		'MAC_SCHEME' '$(MAC_SCHEME)' \
		'MAC_DESTINATION' '$(MAC_DESTINATION)' \
		'CONFIGURATION' '$(CONFIGURATION)' \
		'SIMULATOR_NAME' '$(SIMULATOR_NAME)' \
		'SIMULATOR_ID' '$(SIMULATOR_ID)' \
		'SIMULATOR_BOOT_TIMEOUT_SECONDS' '$(SIMULATOR_BOOT_TIMEOUT_SECONDS)' \
		'DESTINATION_TIMEOUT_SECONDS' '$(DESTINATION_TIMEOUT_SECONDS)' \
		'TEST_EXECUTION_TIMEOUT_SECONDS' '$(TEST_EXECUTION_TIMEOUT_SECONDS)' \
		'TEST_MAXIMUM_EXECUTION_TIMEOUT_SECONDS' '$(TEST_MAXIMUM_EXECUTION_TIMEOUT_SECONDS)' \
		'TEST_RUN_TIMEOUT_SECONDS' '$(TEST_RUN_TIMEOUT_SECONDS)' \
		'DEVICE_ID' '$(DEVICE_ID)' \
		'BUNDLE_ID' '$(BUNDLE_ID)' \
		'XCODE_DEVELOPER_DIR' '$(XCODE_DEVELOPER_DIR)' \
		'XCODE_CONTENTS_DIR' '$(XCODE_CONTENTS_DIR)' \
		'DEVICE_HUB_APP' '$(DEVICE_HUB_APP)' \
		'SIMULATOR_APP' '$(SIMULATOR_APP)' \
		'SIMULATOR_HOST_APP' '$(SIMULATOR_HOST_APP)' \
		'DERIVED_DATA' '~/Library/Developer/Xcode/DerivedData (Xcode default)' \
		'RESULT_BUNDLE_DIR' '$(RESULT_BUNDLE_DIR)' \
		'MAC_RESULT_BUNDLE' '$(MAC_RESULT_BUNDLE)' \
		'PARALLEL_TESTING' '$(PARALLEL_TESTING)' \
		'ONLY_TESTING' '$(ONLY_TESTING)' \
		'MAC_ONLY_TESTING' '$(MAC_ONLY_TESTING)' \
		'LOG_STYLE' '$(LOG_STYLE)' \
		'LOG_LEVEL' '$(LOG_LEVEL)' \
		'LOG_PREDICATE' '$(LOG_PREDICATE)' \
		'XCBEAUTIFY' '$(if $(strip $(XCBEAUTIFY)),$(XCBEAUTIFY),not installed)'

destinations: doctor ## Show destinations accepted by the AVP and macOS schemes.
	@echo 'HappyPianistAVP:'
	xcodebuild -showdestinations -project "$(PROJECT)" -scheme "$(SCHEME)"
	@echo 'HappyPianistMac:'
	xcodebuild -showdestinations $(MAC_XCODEBUILD_COMMON)

list\:simulator: ## List available visionOS Simulator devices.
	xcrun simctl list devices available | grep -A 40 -E '^-- visionOS|Apple Vision Pro' || true

open\:simulator: ## Open DeviceHub (new Xcode) or Simulator (older Xcode).
	@test -n "$(SIMULATOR_HOST_APP)" || { \
		echo 'error: neither DeviceHub.app nor Simulator.app was found'; \
		echo 'checked: $(DEVICE_HUB_APP)'; \
		echo 'checked: $(SIMULATOR_APP)'; \
		echo 'hint: select the intended Xcode, for example:'; \
		echo '  sudo xcode-select -s /Applications/Xcode-beta.app/Contents/Developer'; \
		exit 1; \
	}
	open "$(SIMULATOR_HOST_APP)"

boot\:simulator: ## Boot and wait for the configured Vision Pro Simulator.
	@set -eu; \
		xcrun simctl boot "$(SIMULATOR_ID)" >/dev/null 2>&1 || true; \
		xcrun simctl bootstatus "$(SIMULATOR_ID)" -b & bootstatus_pid=$$!; \
		deadline=$$(($$(date +%s) + $(SIMULATOR_BOOT_TIMEOUT_SECONDS))); \
		while kill -0 "$$bootstatus_pid" 2>/dev/null; do \
			if [ $$(date +%s) -ge "$$deadline" ]; then \
				kill "$$bootstatus_pid" 2>/dev/null || true; \
				wait "$$bootstatus_pid" 2>/dev/null || true; \
				echo "error: Simulator $(SIMULATOR_ID) did not finish booting within $(SIMULATOR_BOOT_TIMEOUT_SECONDS)s" >&2; \
				xcrun simctl list devices | grep -F "$(SIMULATOR_ID)" || true; \
				exit 1; \
			fi; \
			sleep 1; \
		done; \
		wait "$$bootstatus_pid"

shutdown\:simulator: ## Shut down the configured Simulator.
	@xcrun simctl shutdown "$(SIMULATOR_ID)" >/dev/null 2>&1 || true

build\:simulator: doctor ## Build HappyPianistAVP for visionOS Simulator.
	@set -o pipefail; xcodebuild $(XCODEBUILD_COMMON) \
		-destination '$(SIMULATOR_DESTINATION)' \
		CODE_SIGNING_ALLOWED=NO \
		$(XCODEBUILD_FLAGS) \
		build $(XCODEBUILD_OUTPUT)
	@echo 'build:simulator: BUILD SUCCEEDED'

test\:simulator: doctor boot\:simulator ## Run Swift Testing tests on visionOS Simulator.
	@mkdir -p "$(RESULT_BUNDLE_DIR)"
	$(call remove_result_bundle,$(SIMULATOR_RESULT_BUNDLE))
	@set -eum -o pipefail; \
		echo "test:simulator: running with a $(TEST_RUN_TIMEOUT_SECONDS)s action limit"; \
		trap 'if [ -n "$${test_pid:-}" ]; then kill -TERM -- "-$$test_pid" 2>/dev/null || true; wait "$$test_pid" 2>/dev/null || true; fi; exit 130' INT TERM HUP; \
		trap 'status=$$?; xcrun simctl shutdown "$(SIMULATOR_ID)" >/dev/null 2>&1 || true; exit "$$status"' EXIT; \
		xcodebuild $(XCODEBUILD_COMMON) \
		-destination '$(SIMULATOR_DESTINATION)' \
		-destination-timeout "$(DESTINATION_TIMEOUT_SECONDS)" \
		CODE_SIGNING_ALLOWED=NO \
		-parallel-testing-enabled "$(PARALLEL_TESTING)" \
		-test-timeouts-enabled YES \
		-default-test-execution-time-allowance "$(TEST_EXECUTION_TIMEOUT_SECONDS)" \
		-maximum-test-execution-time-allowance "$(TEST_MAXIMUM_EXECUTION_TIMEOUT_SECONDS)" \
		-resultBundlePath "$(SIMULATOR_RESULT_BUNDLE)" \
		$(TEST_SELECTION) \
		$(XCODEBUILD_FLAGS) \
		test $(XCODEBUILD_OUTPUT) & test_pid=$$!; set +m; \
		deadline=$$(($$(date +%s) + $(TEST_RUN_TIMEOUT_SECONDS))); \
		while kill -0 "$$test_pid" 2>/dev/null; do \
			if [ $$(date +%s) -ge "$$deadline" ]; then \
				echo "error: simulator test action exceeded $(TEST_RUN_TIMEOUT_SECONDS)s" >&2; \
				kill -TERM -- "-$$test_pid" 2>/dev/null || true; \
				sleep 5; \
				kill -KILL -- "-$$test_pid" 2>/dev/null || true; \
				wait "$$test_pid" 2>/dev/null || true; \
				xcrun simctl diagnose -b --timeout=60 --output "$(RESULT_BUNDLE_DIR)" --udid "$(SIMULATOR_ID)" || true; \
				exit 124; \
			fi; \
			sleep 1; \
		done; \
		wait "$$test_pid"
	@echo 'test:simulator: TEST SUCCEEDED'

install\:simulator: build\:simulator boot\:simulator ## Install the built app in Simulator.
	@APP_PATH="$$(xcodebuild $(XCODEBUILD_COMMON) \
		-destination '$(SIMULATOR_DESTINATION)' \
		CODE_SIGNING_ALLOWED=NO \
		-showBuildSettings 2>/dev/null | \
		awk -F ' = ' '/^[[:space:]]*TARGET_BUILD_DIR = / { dir=$$2 } /^[[:space:]]*FULL_PRODUCT_NAME = / { name=$$2 } END { if (dir != "" && name != "") print dir "/" name }')"; \
		test -n "$$APP_PATH" && test -d "$$APP_PATH" || { echo "error: unable to locate built app: $$APP_PATH"; exit 1; }; \
		echo "Installing $$APP_PATH"; \
		xcrun simctl install "$(SIMULATOR_ID)" "$$APP_PATH"

launch\:simulator: boot\:simulator ## Launch the installed app in Simulator.
	xcrun simctl launch --terminate-running-process "$(SIMULATOR_ID)" "$(BUNDLE_ID)"

run\:simulator: install\:simulator ## Build, install, and launch in Simulator.
	xcrun simctl launch --terminate-running-process "$(SIMULATOR_ID)" "$(BUNDLE_ID)"

terminate\:simulator: ## Terminate the app in Simulator.
	@xcrun simctl terminate "$(SIMULATOR_ID)" "$(BUNDLE_ID)" >/dev/null 2>&1 || true

logs\:simulator: boot\:simulator ## Stream app-owned structured logs from the configured Simulator.
	xcrun simctl spawn "$(SIMULATOR_ID)" log stream \
		--style "$(LOG_STYLE)" \
		--level "$(LOG_LEVEL)" \
		--predicate '$(LOG_PREDICATE)'

list\:device: ## List paired physical devices known to CoreDevice.
	xcrun devicectl list devices

build\:device: doctor ## Build and sign HappyPianistAVP for the configured physical Vision Pro.
	@test -n "$(DEVICE_ID)" || { echo 'error: set DEVICE_ID=<vision-pro-udid>'; exit 1; }
	@set -o pipefail; xcodebuild $(XCODEBUILD_COMMON) \
		-destination '$(DEVICE_DESTINATION)' \
		$(DEVICE_XCODEBUILD_FLAGS) \
		$(XCODEBUILD_FLAGS) \
		build $(XCODEBUILD_OUTPUT)
	@echo 'build:device: BUILD SUCCEEDED'

test\:device: doctor ## Build, sign, and run tests on the configured physical Vision Pro.
	@test -n "$(DEVICE_ID)" || { echo 'error: set DEVICE_ID=<vision-pro-udid>'; exit 1; }
	@mkdir -p "$(RESULT_BUNDLE_DIR)"
	$(call remove_result_bundle,$(DEVICE_RESULT_BUNDLE))
	@set -o pipefail; xcodebuild $(XCODEBUILD_COMMON) \
		-destination '$(DEVICE_DESTINATION)' \
		-destination-timeout "$(DESTINATION_TIMEOUT_SECONDS)" \
		-test-timeouts-enabled YES \
		-default-test-execution-time-allowance "$(TEST_EXECUTION_TIMEOUT_SECONDS)" \
		-maximum-test-execution-time-allowance "$(TEST_MAXIMUM_EXECUTION_TIMEOUT_SECONDS)" \
		-parallel-testing-enabled "$(PARALLEL_TESTING)" \
		-resultBundlePath "$(DEVICE_RESULT_BUNDLE)" \
		$(TEST_SELECTION) \
		$(DEVICE_XCODEBUILD_FLAGS) \
		$(XCODEBUILD_FLAGS) \
		test $(XCODEBUILD_OUTPUT)
	@echo 'test:device: TEST SUCCEEDED'

install\:device: build\:device ## Install the signed app on the configured physical Vision Pro.
	@APP_PATH="$$(xcodebuild $(XCODEBUILD_COMMON) \
		-destination '$(DEVICE_DESTINATION)' \
		$(DEVICE_XCODEBUILD_FLAGS) \
		-showBuildSettings 2>/dev/null | \
		awk -F ' = ' '/^[[:space:]]*TARGET_BUILD_DIR = / { dir=$$2 } /^[[:space:]]*FULL_PRODUCT_NAME = / { name=$$2 } END { if (dir != "" && name != "") print dir "/" name }')"; \
		test -n "$$APP_PATH" && test -d "$$APP_PATH" || { echo "error: unable to locate built app: $$APP_PATH"; exit 1; }; \
		echo "Installing $$APP_PATH"; \
		xcrun devicectl device install app --device "$(DEVICE_ID)" "$$APP_PATH"

launch\:device: ## Launch the installed app on the configured physical Vision Pro.
	@test -n "$(DEVICE_ID)" || { echo 'error: set DEVICE_ID=<vision-pro-udid>'; exit 1; }
	xcrun devicectl device process launch --device "$(DEVICE_ID)" "$(BUNDLE_ID)"

run\:device: install\:device ## Build, install, and launch on the physical Vision Pro.
	xcrun devicectl device process launch --device "$(DEVICE_ID)" "$(BUNDLE_ID)"

console\:device: install\:device ## Launch on device and attach stdout/stderr until exit.
	xcrun devicectl device process launch --console --device "$(DEVICE_ID)" "$(BUNDLE_ID)"

clean: doctor ## Clean AVP and macOS schemes in Xcode's default DerivedData and remove local test reports.
	xcodebuild $(XCODEBUILD_COMMON) clean
	xcodebuild $(MAC_XCODEBUILD_COMMON) clean
	rm -rf "$(RESULT_BUNDLE_DIR)"
