# SPDX-License-Identifier: GPL-3.0-or-later

CONFIG ?= Debug
DERIVED_DATA := build/DerivedData
XCODEBUILD := xcodebuild -project DictApp.xcodeproj -scheme DictApp -configuration $(CONFIG) \
	-derivedDataPath $(DERIVED_DATA) -destination 'platform=macOS,arch=$(shell uname -m)' -quiet
SWIFT_SOURCES := App Fixtures Packages/DictCore/Package.swift Packages/DictCore/Sources \
	Packages/DictCore/Tests scripts

.PHONY: generate build test test-core test-app smoke e2e matrix eval run package lint format clean

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

# The scripts are owned by the tasks named in Design/m1-tasks.md; until implemented they
# print "not implemented" and fail.
e2e: build
	scripts/e2e.sh $(CONFIG)

matrix: build
	scripts/matrix.sh $(CONFIG)

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
