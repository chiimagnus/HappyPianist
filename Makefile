# HappyPianistAVP visionOS 构建、测试与开发辅助命令。
# 使用 Xcode 默认的 DerivedData，让命令行与 Xcode 共用构建产物。
# 默认值来自 config.yaml，可在命令行覆盖。

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

# 测试报告保存在仓库本地；构建产物使用 Xcode 默认目录：
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
	echo "错误：无法删除旧的测试结果包 $(1)" >&2; \
	exit 1
endef

PARALLEL_TESTING ?= NO
ONLY_TESTING ?=
XCODEBUILD_FLAGS ?= -quiet
DEVICE_XCODEBUILD_FLAGS ?= -allowProvisioningUpdates

# 开发输出默认聚焦于 App 自己的结构化诊断信息。
# 需要更详细的模拟器日志时，可在命令行覆盖这些变量。
LOG_STYLE ?= compact
LOG_LEVEL ?= info
LOG_PREDICATE ?= subsystem == "$(BUNDLE_ID)"

SIMULATOR_DESTINATION = platform=visionOS Simulator,id=$(SIMULATOR_ID)
DEVICE_DESTINATION = platform=visionOS,id=$(DEVICE_ID)
TEST_SELECTION = $(if $(strip $(ONLY_TESTING)),-only-testing:$(ONLY_TESTING),)
MAC_TEST_SELECTION = $(if $(strip $(MAC_ONLY_TESTING)),-only-testing:$(MAC_ONLY_TESTING),)

# 有意省略 -derivedDataPath，让 xcodebuild 对本项目使用与 Xcode 相同的默认
# DerivedData 目录。
XCODEBUILD_COMMON = \
	-project "$(PROJECT)" \
	-scheme "$(SCHEME)" \
	-configuration "$(CONFIGURATION)"

MAC_XCODEBUILD_COMMON = \
	-project "$(PROJECT)" \
	-scheme "$(MAC_SCHEME)" \
	-configuration "$(CONFIGURATION)"

.PHONY: help doctor config destinations clean
.PHONY: build\:mac test\:mac
.PHONY: list\:simulator open\:simulator boot\:simulator shutdown\:simulator
.PHONY: build\:simulator test\:simulator install\:simulator launch\:simulator
.PHONY: run\:simulator terminate\:simulator logs\:simulator
.PHONY: list\:device build\:device test\:device install\:device
.PHONY: launch\:device run\:device console\:device

help: ## 显示可用命令。
	@printf '%s\n' \
		'HappyPianistAVP visionOS Make 目标' \
		'' \
		'macOS：' \
		'  make build:mac              构建独立的 macOS App' \
		'  make test:mac               运行 macOS App 测试' \
		'' \
		'AVP Simulator：' \
		'  make build:simulator        构建 visionOS 模拟器版本' \
		'  make test:simulator         在配置的模拟器上运行全部测试' \
		'  make install:simulator      构建并安装 App' \
		'  make launch:simulator       启动已安装的 App' \
		'  make run:simulator          构建、安装并启动 App' \
		'  make terminate:simulator    终止 App' \
		'  make logs:simulator         输出 App 结构化日志' \
		'  make open:simulator         打开 DeviceHub 或 Simulator' \
		'  make boot:simulator         启动配置的模拟器' \
		'  make shutdown:simulator     关闭配置的模拟器' \
		'' \
		'AVP Device：' \
		'  make build:device           构建并签名 visionOS App' \
		'  make test:device            在配置的 Vision Pro 上运行测试' \
		'  make install:device         构建并安装 App' \
		'  make launch:device          启动已安装的 App' \
		'  make run:device             构建、安装并启动 App' \
		'  make console:device         启动并附加标准输出/错误' \
		'' \
		'发现、配置与维护：' \
		'  make doctor                 检查开发环境' \
		'  make destinations           显示 AVP 和 macOS 可用 destination' \
		'  make list:simulator         列出可用模拟器' \
		'  make list:device            列出已配对真机' \
		'  make config                 显示当前 Make 配置' \
		'  make clean                  清理 AVP、macOS scheme 和本地测试报告' \
		'' \
		'DerivedData：' \
		'  使用 Xcode 默认目录：~/Library/Developer/Xcode/DerivedData/' \
		'  不向 xcodebuild 传入 -derivedDataPath 覆盖值。' \
		'' \
		'覆盖参数：' \
		'  make test:simulator SIMULATOR_ID=<udid>' \
		'  make run:device DEVICE_ID=<udid>' \
		'  make test:simulator ONLY_TESTING=HappyPianistAVPTests/GrandStaffNotationVisualTests' \
		'  make build:device CONFIGURATION=Release' \
		'  make test:mac MAC_ONLY_TESTING=HappyPianistMacTests/MacPracticeViewModelTests' \
		'  make logs:simulator LOG_LEVEL=debug  包含 App 调试诊断信息' \
		'  make build:simulator XCODEBUILD_FLAGS=  显示完整的 xcodebuild 输出'

build\:mac: doctor ## 不使用模拟器构建 HappyPianistMac。
	@xcodebuild $(MAC_XCODEBUILD_COMMON) \
		-destination '$(MAC_DESTINATION)' \
		CODE_SIGNING_ALLOWED=NO \
		$(XCODEBUILD_FLAGS) \
		build
	@echo 'build:mac: 构建成功'

test\:mac: doctor ## 不使用模拟器运行 HappyPianistMac 测试。
	@mkdir -p "$(RESULT_BUNDLE_DIR)"
	$(call remove_result_bundle,$(MAC_RESULT_BUNDLE))
	@xcodebuild $(MAC_XCODEBUILD_COMMON) \
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
		test
	@echo 'test:mac: 测试成功'

doctor: ## 检查所需 Apple 命令行工具和 Xcode 工程是否存在。
	@command -v xcodebuild >/dev/null || { echo '错误：未找到 xcodebuild'; exit 1; }
	@command -v xcrun >/dev/null || { echo '错误：未找到 xcrun'; exit 1; }
	@command -v xcode-select >/dev/null || { echo '错误：未找到 xcode-select'; exit 1; }
	@test -n "$(XCODE_DEVELOPER_DIR)" || { echo '错误：未找到当前 Xcode 开发目录；请运行 sudo xcode-select -s /Applications/Xcode.app/Contents/Developer'; exit 1; }
	@test -d "$(PROJECT)" || { echo '错误：找不到工程：$(PROJECT)'; exit 1; }
	@xcodebuild -version
	@echo 'doctor: 检查通过'

config: ## 打印解析后的 Make 配置。
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
		'XCODEBUILD_FLAGS' '$(XCODEBUILD_FLAGS)'

destinations: doctor ## 显示 AVP 和 macOS scheme 接受的 destination。
	@echo 'HappyPianistAVP 可用 destination：'
	xcodebuild -showdestinations -project "$(PROJECT)" -scheme "$(SCHEME)"
	@echo 'HappyPianistMac 可用 destination：'
	xcodebuild -showdestinations $(MAC_XCODEBUILD_COMMON)

list\:simulator: ## 列出可用的 visionOS 模拟器设备。
	xcrun simctl list devices available | grep -A 40 -E '^-- visionOS|Apple Vision Pro' || true

open\:simulator: ## 打开 DeviceHub（新版 Xcode）或 Simulator（旧版 Xcode）。
	@test -n "$(SIMULATOR_HOST_APP)" || { \
		echo '错误：找不到 DeviceHub.app 或 Simulator.app'; \
		echo '已检查：$(DEVICE_HUB_APP)'; \
		echo '已检查：$(SIMULATOR_APP)'; \
		echo '提示：请选择目标 Xcode，例如：'; \
		echo '  sudo xcode-select -s /Applications/Xcode-beta.app/Contents/Developer'; \
		exit 1; \
	}
	open "$(SIMULATOR_HOST_APP)"

boot\:simulator: ## 启动配置的 Vision Pro 模拟器并等待其就绪。
	@set -eu; \
		xcrun simctl boot "$(SIMULATOR_ID)" >/dev/null 2>&1 || true; \
		xcrun simctl bootstatus "$(SIMULATOR_ID)" -b & bootstatus_pid=$$!; \
		deadline=$$(($$(date +%s) + $(SIMULATOR_BOOT_TIMEOUT_SECONDS))); \
		while kill -0 "$$bootstatus_pid" 2>/dev/null; do \
			if [ $$(date +%s) -ge "$$deadline" ]; then \
				kill "$$bootstatus_pid" 2>/dev/null || true; \
				wait "$$bootstatus_pid" 2>/dev/null || true; \
				echo "错误：模拟器 $(SIMULATOR_ID) 未能在 $(SIMULATOR_BOOT_TIMEOUT_SECONDS) 秒内完成启动" >&2; \
				xcrun simctl list devices | grep -F "$(SIMULATOR_ID)" || true; \
				exit 1; \
			fi; \
			sleep 1; \
		done; \
		wait "$$bootstatus_pid"

shutdown\:simulator: ## 关闭配置的模拟器。
	@xcrun simctl shutdown "$(SIMULATOR_ID)" >/dev/null 2>&1 || true

build\:simulator: doctor ## 为 visionOS 模拟器构建 HappyPianistAVP。
	@xcodebuild $(XCODEBUILD_COMMON) \
		-destination '$(SIMULATOR_DESTINATION)' \
		CODE_SIGNING_ALLOWED=NO \
		$(XCODEBUILD_FLAGS) \
		build
	@echo 'build:simulator: 构建成功'

test\:simulator: doctor boot\:simulator ## 在 visionOS 模拟器上运行 Swift Testing 测试。
	@mkdir -p "$(RESULT_BUNDLE_DIR)"
	$(call remove_result_bundle,$(SIMULATOR_RESULT_BUNDLE))
	@set -eum; \
		echo "test:simulator：运行总时限为 $(TEST_RUN_TIMEOUT_SECONDS) 秒"; \
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
		test & test_pid=$$!; set +m; \
		deadline=$$(($$(date +%s) + $(TEST_RUN_TIMEOUT_SECONDS))); \
		while kill -0 "$$test_pid" 2>/dev/null; do \
			if [ $$(date +%s) -ge "$$deadline" ]; then \
				echo "错误：模拟器测试超过 $(TEST_RUN_TIMEOUT_SECONDS) 秒总时限" >&2; \
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
	@echo 'test:simulator: 测试成功'

install\:simulator: build\:simulator boot\:simulator ## 将构建好的 App 安装到模拟器。
	@APP_PATH="$$(xcodebuild $(XCODEBUILD_COMMON) \
		-destination '$(SIMULATOR_DESTINATION)' \
		CODE_SIGNING_ALLOWED=NO \
		-showBuildSettings 2>/dev/null | \
		awk -F ' = ' '/^[[:space:]]*TARGET_BUILD_DIR = / { dir=$$2 } /^[[:space:]]*FULL_PRODUCT_NAME = / { name=$$2 } END { if (dir != "" && name != "") print dir "/" name }')"; \
		test -n "$$APP_PATH" && test -d "$$APP_PATH" || { echo "error: unable to locate built app: $$APP_PATH"; exit 1; }; \
		echo "正在安装 $$APP_PATH"; \
		xcrun simctl install "$(SIMULATOR_ID)" "$$APP_PATH"

launch\:simulator: boot\:simulator ## 在模拟器中启动已安装的 App。
	xcrun simctl launch --terminate-running-process "$(SIMULATOR_ID)" "$(BUNDLE_ID)"

run\:simulator: install\:simulator ## 构建、安装并在模拟器中启动。
	xcrun simctl launch --terminate-running-process "$(SIMULATOR_ID)" "$(BUNDLE_ID)"

terminate\:simulator: ## 终止模拟器中的 App。
	@xcrun simctl terminate "$(SIMULATOR_ID)" "$(BUNDLE_ID)" >/dev/null 2>&1 || true

logs\:simulator: boot\:simulator ## 输出配置模拟器中 App 自己的结构化日志。
	xcrun simctl spawn "$(SIMULATOR_ID)" log stream \
		--style "$(LOG_STYLE)" \
		--level "$(LOG_LEVEL)" \
		--predicate '$(LOG_PREDICATE)'

list\:device: ## 列出 CoreDevice 识别到的已配对真机。
	xcrun devicectl list devices

build\:device: doctor ## 为配置的 Vision Pro 真机构建并签名 HappyPianistAVP。
	@test -n "$(DEVICE_ID)" || { echo '错误：请设置 DEVICE_ID=<vision-pro-udid>'; exit 1; }
	@xcodebuild $(XCODEBUILD_COMMON) \
		-destination '$(DEVICE_DESTINATION)' \
		$(DEVICE_XCODEBUILD_FLAGS) \
		$(XCODEBUILD_FLAGS) \
		build
	@echo 'build:device: 构建成功'

test\:device: doctor ## 为配置的 Vision Pro 真机构建、签名并运行测试。
	@test -n "$(DEVICE_ID)" || { echo '错误：请设置 DEVICE_ID=<vision-pro-udid>'; exit 1; }
	@mkdir -p "$(RESULT_BUNDLE_DIR)"
	$(call remove_result_bundle,$(DEVICE_RESULT_BUNDLE))
	@xcodebuild $(XCODEBUILD_COMMON) \
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
		test
	@echo 'test:device: 测试成功'

install\:device: build\:device ## 将签名后的 App 安装到配置的 Vision Pro 真机。
	@APP_PATH="$$(xcodebuild $(XCODEBUILD_COMMON) \
		-destination '$(DEVICE_DESTINATION)' \
		$(DEVICE_XCODEBUILD_FLAGS) \
		-showBuildSettings 2>/dev/null | \
		awk -F ' = ' '/^[[:space:]]*TARGET_BUILD_DIR = / { dir=$$2 } /^[[:space:]]*FULL_PRODUCT_NAME = / { name=$$2 } END { if (dir != "" && name != "") print dir "/" name }')"; \
		test -n "$$APP_PATH" && test -d "$$APP_PATH" || { echo "error: unable to locate built app: $$APP_PATH"; exit 1; }; \
		echo "正在安装 $$APP_PATH"; \
		xcrun devicectl device install app --device "$(DEVICE_ID)" "$$APP_PATH"

launch\:device: ## 在配置的 Vision Pro 真机上启动已安装的 App。
	@test -n "$(DEVICE_ID)" || { echo '错误：请设置 DEVICE_ID=<vision-pro-udid>'; exit 1; }
	xcrun devicectl device process launch --device "$(DEVICE_ID)" "$(BUNDLE_ID)"

run\:device: install\:device ## 构建、安装并在 Vision Pro 真机上启动。
	xcrun devicectl device process launch --device "$(DEVICE_ID)" "$(BUNDLE_ID)"

console\:device: install\:device ## 在真机上启动并附加标准输出/错误，直到进程退出。
	xcrun devicectl device process launch --console --device "$(DEVICE_ID)" "$(BUNDLE_ID)"

clean: doctor ## 清理 Xcode 默认 DerivedData 中的 AVP/macOS scheme，并删除本地测试报告。
	xcodebuild $(XCODEBUILD_COMMON) clean
	xcodebuild $(MAC_XCODEBUILD_COMMON) clean
	rm -rf "$(RESULT_BUNDLE_DIR)"
