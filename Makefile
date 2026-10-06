# SPDX-License-Identifier: GPL-3.0-or-later

CONFIG ?= Debug
DERIVED_DATA := build/DerivedData
XCODEBUILD := xcodebuild -project DictApp.xcodeproj -scheme DictApp -configuration $(CONFIG) \
	-derivedDataPath $(DERIVED_DATA) -destination 'platform=macOS,arch=$(shell uname -m)' -quiet
SWIFT_SOURCES := App Fixtures Packages/DictCore/Package.swift Packages/DictCore/Sources \
	Packages/DictCore/Tests scripts tools/build-dict/Package.swift tools/build-dict/Sources \
	tools/build-dict/Tests

.PHONY: generate build test test-core test-app test-dict dict dict-stats dict-update dict-cloud-export dict-cloud-verify smoke window-test e2e e2e-live matrix eval import-key run run-mock stop-mock test-mock package lint format clean

generate:
	xcodegen generate --quiet

build: generate
	$(XCODEBUILD) build

test: test-core test-dict test-mock test-app smoke

test-core:
	cd Packages/DictCore && swift test

# The dictionary builder against hand-written fixtures; no network.
test-dict:
	cd tools/build-dict && swift test

# Downloads the pinned inputs in tools/build-dict/manifest.json into build/dict/cache/ (kept
# there named by SHA-256 and reused when present), then writes build/dict/dict-en-zh.sqlite with
# its LICENSE and ATTRIBUTION. Fails with instructions when upstream has replaced a snapshot.
dict:
	swift build -c release --package-path tools/build-dict
	tools/build-dict/.build/release/build-dict build

# Coverage of the most frequent words and lookup timing of build/dict/dict-en-zh.sqlite.
dict-stats:
	swift build -c release --package-path tools/build-dict
	tools/build-dict/.build/release/build-dict stats

# Pins the current upstream files in tools/build-dict/manifest.json, rebuilds, and prints the
# figures before and after; review them, then commit the manifest.
dict-update:
	swift build -c release --package-path tools/build-dict
	tools/build-dict/.build/release/build-dict update

# Writes build/cloud-dict/data.sql, the INSERTs that fill the cloud D1 database (schema in
# tools/cloud-dict/schema.sql) from build/dict/dict-en-zh.sqlite; run `make dict` first.
dict-cloud-export:
	mkdir -p build/cloud-dict
	node tools/cloud-dict/export.mjs build/dict/dict-en-zh.sqlite build/cloud-dict/data.sql

# Loads the schema and data.sql into wrangler's local D1 under build/cloud-dict/d1 and checks
# it against the source sqlite. Local only: needs no Cloudflare account.
dict-cloud-verify: dict-cloud-export tools/cloud-dict/node_modules
	node tools/cloud-dict/verify.mjs build/dict/dict-en-zh.sqlite build/cloud-dict/data.sql \
		build/cloud-dict/d1

tools/cloud-dict/node_modules: tools/cloud-dict/package-lock.json
	npm ci --prefix tools/cloud-dict
	touch $@

# The mock model's answering mode (scripts/fake-model.py) on a free port; no network.
test-mock:
	python3 scripts/fake-model-test.py

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

# The Debug app against the local mock model on 127.0.0.1:8767: no key, no tokens.
run-mock: build
	scripts/mock-model.sh start

stop-mock:
	scripts/mock-model.sh stop

package: generate
	scripts/package.sh

lint:
	swift format lint --strict --recursive $(SWIFT_SOURCES)

format:
	swift format --in-place --recursive $(SWIFT_SOURCES)

clean:
	rm -rf build DictApp.xcodeproj Packages/DictCore/.build tools/build-dict/.build
