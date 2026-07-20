# HappyPianistAVP visionOS build/test/run helpers.
# Defaults are copied from config.yaml and can be overridden on the command line.

.DEFAULT_GOAL := help
.NOTPARALLEL:

PROJECT ?= HappyPianist.xcodeproj
SCHEME ?= HappyPianistAVP
APP_NAME ?= HappyPianistAVP
BUNDLE_ID ?= com.chiimagnus.HappyPianistAVP
CONFIGURATION ?= Debug

SIMULATOR_ID ?= 86364D5F-BCCF-48C5-AF79-8154E5689FA3
SIMULATOR_NAME ?= Apple Vision Pro
DEVICE_ID ?= A687F5B3-44BC-5C55-B5C4-22A807A27C6F

DERIVED_DATA_PATH ?= .build/DerivedData
RESULT_BUNDLE_DIR ?= .build/TestResults
SIMULATOR_RESULT_BUNDLE ?= $(RESULT_BUNDLE_DIR)/HappyPianistAVP-Simulator.xcresult
DEVICE_RESULT_BUNDLE ?= $(RESULT_BUNDLE_DIR)/HappyPianistAVP-Device.xcresult

PARALLEL_TESTING ?= NO
ONLY_TESTING ?=
XCODEBUILD_FLAGS ?=
DEVICE_XCODEBUILD_FLAGS ?= -allowProvisioningUpdates

SIMULATOR_DESTINATION = platform=visionOS Simulator,id=$(SIMULATOR_ID)
DEVICE_DESTINATION = platform=visionOS,id=$(DEVICE_ID)
SIMULATOR_APP_PATH = $(DERIVED_DATA_PATH)/Build/Products/$(CONFIGURATION)-xrsimulator/$(APP_NAME).app
DEVICE_APP_PATH = $(DERIVED_DATA_PATH)/Build/Products/$(CONFIGURATION)-xros/$(APP_NAME).app
TEST_SELECTION = $(if $(strip $(ONLY_TESTING)),-only-testing:$(ONLY_TESTING),)

XCODEBUILD_COMMON = \
	-project "$(PROJECT)" \
	-scheme "$(SCHEME)" \
	-configuration "$(CONFIGURATION)" \
	-derivedDataPath "$(DERIVED_DATA_PATH)"

.PHONY: help doctor config destinations clean \
	build test run \
	list\:simulator open\:simulator boot\:simulator shutdown\:simulator \
	build\:simulator test\:simulator install\:simulator launch\:simulator \
	run\:simulator terminate\:simulator logs\:simulator \
	list\:device build\:device test\:device install\:device \
	launch\:device run\:device console\:device

help: ## Show available commands.
	@printf '%s\n' \
		'HappyPianistAVP visionOS Make targets' \
		'' \
		'Default Simulator shortcuts:' \
		'  make build                  Alias for make build:simulator' \
		'  make test                   Alias for make test:simulator' \
		'  make run                    Alias for make run:simulator' \
		'  make clean                  Remove local DerivedData and test results' \
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
		'  make destinations' \
		'  make list:simulator' \
		'  make list:device' \
		'  make config' \
		'' \
		'Overrides:' \
		'  make test:simulator SIMULATOR_ID=<udid>' \
		'  make run:device DEVICE_ID=<udid>' \
		'  make test:simulator ONLY_TESTING=HappyPianistAVPTests/GrandStaffNotationVisualTests' \
		'  make build:device CONFIGURATION=Release'

build: build\:simulator ## Build for the configured Vision Pro Simulator.

test: test\:simulator ## Run tests on the configured Vision Pro Simulator.

run: run\:simulator ## Build, install, and launch in Simulator.

doctor: ## Verify the required Apple command-line tools and project are present.
	@command -v xcodebuild >/dev/null || { echo 'error: xcodebuild not found'; exit 1; }
	@command -v xcrun >/dev/null || { echo 'error: xcrun not found'; exit 1; }
	@test -d "$(PROJECT)" || { echo 'error: project not found: $(PROJECT)'; exit 1; }
	@xcodebuild -version
	@echo 'doctor: OK'

config: ## Print the resolved Make configuration.
	@printf '%-26s %s\n' \
		'PROJECT' '$(PROJECT)' \
		'SCHEME' '$(SCHEME)' \
		'CONFIGURATION' '$(CONFIGURATION)' \
		'SIMULATOR_NAME' '$(SIMULATOR_NAME)' \
		'SIMULATOR_ID' '$(SIMULATOR_ID)' \
		'DEVICE_ID' '$(DEVICE_ID)' \
		'BUNDLE_ID' '$(BUNDLE_ID)' \
		'DERIVED_DATA_PATH' '$(DERIVED_DATA_PATH)' \
		'ONLY_TESTING' '$(ONLY_TESTING)'

destinations: doctor ## Show destinations accepted by the AVP scheme.
	xcodebuild -showdestinations -project "$(PROJECT)" -scheme "$(SCHEME)"

list\:simulator: ## List available visionOS Simulator devices.
	xcrun simctl list devices available | grep -A 40 -E '^-- visionOS|Apple Vision Pro' || true

open\:simulator: ## Open the Simulator app.
	open -a Simulator

boot\:simulator: ## Boot and wait for the configured Vision Pro Simulator.
	@xcrun simctl boot "$(SIMULATOR_ID)" >/dev/null 2>&1 || true
	xcrun simctl bootstatus "$(SIMULATOR_ID)" -b

shutdown\:simulator: ## Shut down the configured Simulator.
	@xcrun simctl shutdown "$(SIMULATOR_ID)" >/dev/null 2>&1 || true

build\:simulator: doctor ## Build HappyPianistAVP for visionOS Simulator.
	xcodebuild $(XCODEBUILD_COMMON) \
		-destination '$(SIMULATOR_DESTINATION)' \
		CODE_SIGNING_ALLOWED=NO \
		$(XCODEBUILD_FLAGS) \
		build

test\:simulator: doctor boot\:simulator ## Run Swift Testing tests on visionOS Simulator.
	@mkdir -p "$(RESULT_BUNDLE_DIR)"
	@rm -rf "$(SIMULATOR_RESULT_BUNDLE)"
	xcodebuild $(XCODEBUILD_COMMON) \
		-destination '$(SIMULATOR_DESTINATION)' \
		CODE_SIGNING_ALLOWED=NO \
		-parallel-testing-enabled "$(PARALLEL_TESTING)" \
		-resultBundlePath "$(SIMULATOR_RESULT_BUNDLE)" \
		$(TEST_SELECTION) \
		$(XCODEBUILD_FLAGS) \
		test

install\:simulator: build\:simulator boot\:simulator ## Install the built app in Simulator.
	@test -d "$(SIMULATOR_APP_PATH)" || { echo 'error: app not found: $(SIMULATOR_APP_PATH)'; exit 1; }
	xcrun simctl install "$(SIMULATOR_ID)" "$(SIMULATOR_APP_PATH)"

launch\:simulator: boot\:simulator ## Launch the installed app in Simulator.
	xcrun simctl launch --terminate-running-process "$(SIMULATOR_ID)" "$(BUNDLE_ID)"

run\:simulator: install\:simulator ## Build, install, and launch in Simulator.
	xcrun simctl launch --terminate-running-process "$(SIMULATOR_ID)" "$(BUNDLE_ID)"

terminate\:simulator: ## Terminate the app in Simulator.
	@xcrun simctl terminate "$(SIMULATOR_ID)" "$(BUNDLE_ID)" >/dev/null 2>&1 || true

logs\:simulator: boot\:simulator ## Stream app logs from the configured Simulator.
	xcrun simctl spawn "$(SIMULATOR_ID)" log stream \
		--style compact \
		--level debug \
		--predicate 'process == "$(APP_NAME)" OR subsystem == "$(BUNDLE_ID)"'

list\:device: ## List paired physical devices known to CoreDevice.
	xcrun devicectl list devices

build\:device: doctor ## Build and sign HappyPianistAVP for the configured physical Vision Pro.
	@test -n "$(DEVICE_ID)" || { echo 'error: set DEVICE_ID=<vision-pro-udid>'; exit 1; }
	xcodebuild $(XCODEBUILD_COMMON) \
		-destination '$(DEVICE_DESTINATION)' \
		$(DEVICE_XCODEBUILD_FLAGS) \
		$(XCODEBUILD_FLAGS) \
		build

test\:device: doctor ## Build, sign, and run tests on the configured physical Vision Pro.
	@test -n "$(DEVICE_ID)" || { echo 'error: set DEVICE_ID=<vision-pro-udid>'; exit 1; }
	@mkdir -p "$(RESULT_BUNDLE_DIR)"
	@rm -rf "$(DEVICE_RESULT_BUNDLE)"
	xcodebuild $(XCODEBUILD_COMMON) \
		-destination '$(DEVICE_DESTINATION)' \
		-parallel-testing-enabled "$(PARALLEL_TESTING)" \
		-resultBundlePath "$(DEVICE_RESULT_BUNDLE)" \
		$(TEST_SELECTION) \
		$(DEVICE_XCODEBUILD_FLAGS) \
		$(XCODEBUILD_FLAGS) \
		test

install\:device: build\:device ## Install the signed app on the configured physical Vision Pro.
	@test -d "$(DEVICE_APP_PATH)" || { echo 'error: app not found: $(DEVICE_APP_PATH)'; exit 1; }
	xcrun devicectl device install app --device "$(DEVICE_ID)" "$(DEVICE_APP_PATH)"

launch\:device: ## Launch the installed app on the configured physical Vision Pro.
	@test -n "$(DEVICE_ID)" || { echo 'error: set DEVICE_ID=<vision-pro-udid>'; exit 1; }
	xcrun devicectl device process launch --device "$(DEVICE_ID)" "$(BUNDLE_ID)"

run\:device: install\:device ## Build, install, and launch on the physical Vision Pro.
	xcrun devicectl device process launch --device "$(DEVICE_ID)" "$(BUNDLE_ID)"

console\:device: install\:device ## Launch on device and attach stdout/stderr until exit.
	xcrun devicectl device process launch --console --device "$(DEVICE_ID)" "$(BUNDLE_ID)"

clean: ## Remove Make-managed DerivedData and result bundles.
	rm -rf "$(DERIVED_DATA_PATH)" "$(RESULT_BUNDLE_DIR)"
