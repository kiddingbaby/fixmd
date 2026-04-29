SHELL := /bin/bash

.PHONY: test check contract

test:
	bash tests/smoke.sh

contract:
	python3 tests/validate_contract.py

check:
	bash -n scripts/fixmd.sh
	bash tests/smoke.sh
	python3 tests/validate_contract.py
