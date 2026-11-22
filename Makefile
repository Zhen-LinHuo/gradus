GUILE = guix shell --pure -q guix guile -- guile

.PHONY: check

check:
	$(GUILE) -L . tests/script.scm
