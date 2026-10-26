# arch-kam — shamanic rituals for Arch-based systems
# Ritüelleri derler, kurar ve denetler.

PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin
COMPLETIONDIR = $(PREFIX)/share/bash-completion/completions
DOCDIR = $(PREFIX)/share/doc/arch-kam

RITUALS = arch-kam.sh lib.sh doctor.sh hibernate-enabler.sh battery.sh \
          bootloader-bg.sh clean.sh pacdiff.sh kernel.sh mirror.sh \
          sysupdate.sh efi.sh microcode.sh mounts.sh btrfs.sh zram.sh \
          security.sh

.PHONY: all install uninstall lint test doctor clean-dist

all: lint

help:
	@echo "Kullanım:"
	@echo "  make install      Tüm ritüelleri kur"
	@echo "  make uninstall    Kurulan ritüelleri kaldır"
	@echo "  make lint         shellcheck ile sözdizimi denetimi"
	@echo "  make test         Temel davranış testleri"
	@echo "  make doctor       Salt okunur sistem teşhisi"
	@echo "  make clean-dist   Dağıtım paketini üret"

install: $(RITUALS)
	install -d $(DESTDIR)$(BINDIR)
	install -m 755 $(RITUALS) $(DESTDIR)$(BINDIR)/
	install -d $(DESTDIR)$(DOCDIR)
	install -m 644 README.md LICENSE $(DESTDIR)$(DOCDIR)/ 2>/dev/null || true
	@echo "Kurulum tamam: $(DESTDIR)$(BINDIR)"
	@echo "Denetim: arch-kam doctor"

uninstall:
	rm -f $(addprefix $(DESTDIR)$(BINDIR)/,$(RITUALS))
	@echo "Kaldırıldı: $(DESTDIR)$(BINDIR)"

lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		echo "shellcheck ile denetleniyor..."; \
		shellcheck -S warning *.sh || true; \
	else \
		echo "shellcheck kurulu değil; bash -n ile denetleniyor..."; \
		for f in *.sh; do bash -n "$$f" || exit 1; done; \
		echo "Sözdizimi tamam."; \
	fi

test: lint
	@echo "Temel testler..."
	@for f in *.sh; do \
		test -x "$$f" || { echo "Çalıştırılabilir değil: $$f"; exit 1; }; \
	done
	@./arch-kam.sh --help >/dev/null || { echo "arch-kam --help başarısız"; exit 1; }
	@./doctor.sh --help >/dev/null || { echo "doctor --help başarısız"; exit 1; }
	@./pacdiff.sh --list >/dev/null || { echo "pacdiff --list başarısız"; exit 1; }
	@echo "Testler tamam."

doctor:
	@./doctor.sh

clean-dist:
	rm -rf dist/arch-kam
	mkdir -p dist/arch-kam
	cp $(RITUALS) README.md LICENSE Makefile dist/arch-kam/
	tar czf arch-kam-$$(date +%Y%m%d).tar.gz -C dist arch-kam
	@echo "Paket: arch-kam-$$(date +%Y%m%d).tar.gz"
