GUILE = guix shell --pure -q guix guile -- guile

.PHONY: check walkthrough iso vm-install vm-clean

check:
	$(GUILE) -L . tests/script.scm
	$(GUILE) -L . tests/answers.scm
	$(GUILE) -L . tests/fs.scm
	$(GUILE) -L . tests/package-groups.scm
	$(GUILE) -L . tests/selection.scm
	$(GUILE) -L . tests/storage.scm
	$(GUILE) -L . tests/wizard.scm
	$(GUILE) -L . tests/wizard-set.scm
	$(GUILE) -L . tests/render.scm
	$(GUILE) -L . tests/serialize.scm
	@echo 'checking that the front-end loads'
	guix shell --pure -q guix guile guile-ncurses -- guile -L . -c '(use-modules (gradus tui))'

# The wizard under a pty, in validation mode: every page, every check,
# nothing written.  Safe to run on any host.
walkthrough:
	python3 scripts/rig/pty-walk.py

# The live medium.  Embeds the source tree from .build/gradus-src.tar.gz.
iso: .build/gradus-src.tar.gz
	guix system image --image-type=iso9660 --image-size=9G conf/live.scm \
	  | tee .build/iso-path

.build/gradus-src.tar.gz:
	@mkdir -p .build
	tar czf $@ --exclude=.git --exclude=.build .

# One cell of the install matrix:  make vm-install FS=ext4 FW=bios
# (FS: ext4|btrfs|xfs — FW: bios|uefi; uefi needs OVMF=<firmware image>)
vm-install:
	scripts/rig/vm-install.sh $(FS) $(FW)

vm-clean:
	rm -rf .build/vm-*
