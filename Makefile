SHELL := /usr/bin/env bash

.PHONY: check validate test qmllint integration companion-check hardware-test dependency-audit performance-test performance-check version-check

check: validate test qmllint

validate:
	python3 scripts/validate.py
	python3 scripts/validate_version.py
	python3 scripts/config_tool.py validate config/defaults.json
	python3 -m py_compile scripts/config_tool.py scripts/dependency_audit.py scripts/hardware_test.py scripts/performance_check.py scripts/performance_test.py scripts/process_snapshot.py scripts/process_watchdog.py scripts/support_bundle.py scripts/validate.py scripts/validate_version.py
	bash -n cli/omanome input/clipboard-capture.sh input/system-state.sh input/wifi-scan.sh input/bluetooth-scan.sh input/rotation-monitor.sh input/sensor-info.sh input/companion-info.sh input/effects-info.sh input/force-quit.sh input/audio-devices.sh

test:
	python3 -m unittest discover -s tests -p 'test_*.py' -v

qmllint:
	@if command -v qmllint >/dev/null 2>&1 || [ -x /usr/lib/qt6/bin/qmllint ]; then \
		QMLLINT=$$(command -v qmllint 2>/dev/null || printf '%s' /usr/lib/qt6/bin/qmllint); \
		IMPORT_ROOT=$$(mktemp -d); \
		trap 'rm -rf "$$IMPORT_ROOT"' EXIT; \
		mkdir -p "$$IMPORT_ROOT/qs"; \
		ln -sfn /usr/share/omarchy/shell/Commons "$$IMPORT_ROOT/qs/Commons"; \
		ln -sfn /usr/share/omarchy/shell/Ui "$$IMPORT_ROOT/qs/Ui"; \
		find shell -name '*.qml' -print0 | xargs -0 "$$QMLLINT" -I "$$IMPORT_ROOT" -I /usr/share/omarchy/shell; \
	else \
		echo 'qmllint not installed; skipped'; \
	fi

integration:
	@command -v omarchy >/dev/null 2>&1 || { echo 'Omarchy integration requires a running Omarchy installation'; exit 2; }
	omarchy plugin validate .
	$(MAKE) qmllint
	./cli/omanome doctor

companion-check:
	$(MAKE) -C hypr/omanome-hypr check

hardware-test:
	python3 scripts/hardware_test.py --fixture tests/fixtures/hardware-tablet.json --json

dependency-audit:
	python3 scripts/dependency_audit.py --json

performance-test:
	python3 scripts/performance_test.py --json

performance-check:
	python3 scripts/performance_check.py --json

version-check:
	python3 scripts/validate_version.py 0.8.0
