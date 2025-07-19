IMAGE ?= sms-gateway:test

.PHONY: test lint build

test:
	docker build --build-arg INSTALL_DEV_DEPS=true -t $(IMAGE) .
	docker run --rm -e CI_MODE=true $(IMAGE) pytest -q

lint:
	ruff check .
	black --check .

build:
	docker build --build-arg INSTALL_DEV_DEPS=false -t $(IMAGE) .
