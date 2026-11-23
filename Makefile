GUILE = guix shell --pure -q guix guile -- guile

.PHONY: check

check:
	$(GUILE) -L . tests/script.scm
	$(GUILE) -L . tests/answers.scm
	$(GUILE) -L . tests/render.scm
	$(GUILE) -L . tests/serialize.scm
