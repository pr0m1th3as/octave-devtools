## Makefile for the devtools package.
##
## The build must never fail.  devtools.mcp needs nothing from here, and a machine
## with no working compiler must still install the package and use the
## read-only server; what it loses is the output capture the evaluating server
## uses, and devtools.mcpEval says so rather than misbehaving.

MKOCTFILE ?= mkoctfile

all: capture guard

capture:
	@if $(MKOCTFILE) __devtools_capture__.cc > devtools_build.log 2>&1; then \
	  echo "devtools: built __devtools_capture__.oct"; \
	else \
	  echo "devtools: no working compiler for __devtools_capture__.cc."; \
	  echo "devtools: the read-only server is unaffected; the evaluating server"; \
	  echo "devtools: will take a subprocess's output back and print it through"; \
	  echo "devtools: the interpreter instead of capturing it at the descriptor,"; \
	  echo "devtools: refusing only the two forms that cannot be taken back."; \
	  echo "devtools: Build log follows."; \
	  cat devtools_build.log; \
	fi

guard:
	@if $(MKOCTFILE) __devtools_guard__.cc > devtools_build.log 2>&1; then \
	  echo "devtools: built __devtools_guard__.oct"; \
	else \
	  echo "devtools: no working compiler for __devtools_guard__.cc."; \
	  echo "devtools: the evaluating server will run without a deadline, so code"; \
	  echo "devtools: that does not return holds it until the host restarts it."; \
	  cat devtools_build.log; \
	fi

clean:
	-rm -f *.o *.oct devtools_build.log

.PHONY: all capture guard clean
