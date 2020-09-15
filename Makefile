DOC	= course-intro
TEX	= $(DOC).tex
PDF	= $(DOC).pdf

all: $(PDF)

$(PDF): $(TEX) Makefile settings.tex course.tex
	$(MAKE) spell
	pdflatex $(OPTS) -shell-escape $<
	@rm -f $(@:%.pdf=%-orig.pdf)
	@mv $@ $(@:%.pdf=%-orig.pdf)
	@echo I: Compressing $@
	gs -sDEVICE=pdfwrite -dCompatibilityLevel=1.5 -dPDFSETTINGS=/prepress -dNOPAUSE -dQUIET -dBATCH -sOutputFile=$@ $(@:%.pdf=%-orig.pdf)
	@$(MAKE partial-clean)


spell: $(TEX)
	aspell -c $<

check: $(TEX)
	chktex $<

partial-clean:
	rm -f *.aux *.log *.nav *.out *.snm *.toc

clean: partial-clean
	rm -f *.pdf
