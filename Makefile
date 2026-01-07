IMAGE ?= sms-gateway:test

.PHONY: test lint build

test:
	bash scripts/run_tests.sh

lint:
	ruff check .
	black --check .

build:
	docker build --build-arg INSTALL_DEV_DEPS=false -t $(IMAGE) .
