SHELL := /bin/bash

.PHONY: test check

test:
	bash tests/smoke.sh

check:
	bash -n scripts/fixmd.sh
	bash tests/smoke.sh
