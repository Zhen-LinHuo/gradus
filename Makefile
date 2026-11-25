GUILE = guix shell --pure -q guix guile -- guile

.PHONY: check

check:
	$(GUILE) -L . tests/script.scm
	$(GUILE) -L . tests/answers.scm
	$(GUILE) -L . tests/storage.scm
	$(GUILE) -L . tests/wizard.scm
	$(GUILE) -L . tests/wizard-set.scm
	$(GUILE) -L . tests/render.scm
	$(GUILE) -L . tests/serialize.scm
	@echo 'checking that the front-end loads'
	guix shell --pure -q guix guile guile-ncurses -- guile -L . -c '(use-modules (gradus tui))'
