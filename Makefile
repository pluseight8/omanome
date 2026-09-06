SHELL := /usr/bin/env bash

.PHONY: check validate test qmllint integration

check: validate test qmllint

validate:
	python3 scripts/validate.py
	bash -n cli/omanome input/clipboard-capture.sh

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
