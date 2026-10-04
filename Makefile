# SPDX-License-Identifier: GPL-3.0-or-later

CONFIG ?= Debug
DERIVED_DATA := build/DerivedData
XCODEBUILD := xcodebuild -project DictApp.xcodeproj -scheme DictApp -configuration $(CONFIG) \
	-derivedDataPath $(DERIVED_DATA) -destination 'platform=macOS,arch=$(shell uname -m)' -quiet
SWIFT_SOURCES := App Fixtures Packages/DictCore/Package.swift Packages/DictCore/Sources \
	Packages/DictCore/Tests scripts

.PHONY: generate build test test-core test-app smoke window-test e2e e2e-live matrix eval import-key run package lint format clean

generate:
	xcodegen generate --quiet

build: generate
	$(XCODEBUILD) build

test: test-core test-app smoke

test-core:
	cd Packages/DictCore && swift test

test-app: generate
	$(XCODEBUILD) test

smoke: build
	swift scripts/smoke-test.swift "$$(scripts/app-path.sh $(CONFIG))"

# Takes focus: brings the app's windows to the front, so it is not part of `make test`.
window-test: build
	swift scripts/window-test.swift "$$(scripts/app-path.sh $(CONFIG))"

# The scripts are owned by the tasks named in Design/m1-tasks.md; until implemented they
# print "not implemented" and fail.
e2e: build
	scripts/e2e.sh $(CONFIG)

matrix: build
	scripts/matrix.sh $(CONFIG)

# The real model end to end: needs the network, `make import-key`, and costs a few cents at
# most. Never part of `make test` or `make e2e`.
e2e-live: build
	scripts/e2e-live.sh

# Saves OPENAI_API_KEY from .env into the Debug app's own Keychain item and selects OpenAI.
import-key: build
	scripts/import-key.sh $(MODEL)

eval:
	SUITE="$(SUITE)" RUNS="$(RUNS)" scripts/eval.sh

run: build
	open "$$(scripts/app-path.sh $(CONFIG))"

package: generate
	scripts/package.sh

lint:
	swift format lint --strict --recursive $(SWIFT_SOURCES)

format:
	swift format --in-place --recursive $(SWIFT_SOURCES)

clean:
	rm -rf build DictApp.xcodeproj Packages/DictCore/.build
