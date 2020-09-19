NAME	= course-intro
TEX	= $(NAME).tex
PDF	= $(NAME).pdf
SCRIPT	= $(NAME).sh

all: $(PDF)

$(PDF): $(TEX) Makefile settings.tex course.tex
	@echo "I: Spellchecking $<" >&2
	$(MAKE) spell
	@echo "I: Building $<" >&2
	pdflatex $(OPTS) -shell-escape $<
	@rm -f $(@:%.pdf=%-orig.pdf)
	@mv $@ $(@:%.pdf=%-orig.pdf)
	@echo "I: Compressing $<" >&2
	gs -sDEVICE=pdfwrite -dCompatibilityLevel=1.5 -dPDFSETTINGS=/prepress -dNOPAUSE -dQUIET -dBATCH -sOutputFile=$@ $(@:%.pdf=%-orig.pdf)
	@$(MAKE partial-clean)


spell: $(TEX) $(SCRIPT)
	aspell -c --home-dir=. $<
	aspell -c --home-dir=. $(SCRIPT)

check: $(TEX)
	chktex $<

partial-clean:
	rm -f *.aux *.log *.nav *.out *.snm *.toc

clean: partial-clean
	rm -f *.pdf
