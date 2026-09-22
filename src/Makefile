## Makefile for the devtools package.
##
## The build must never fail.  devtools.mcp needs nothing from here, and a machine
## with no working compiler must still install the package and use the
## read-only server; what it loses is the output capture the evaluating server
## uses, and devtools.mcpEval says so rather than misbehaving.

MKOCTFILE ?= mkoctfile

all: capture guard spawn parse

capture:
	@if $(MKOCTFILE) __devtools_capture__.cc > devtools_capture.log 2>&1; then \
	  echo "devtools: built __devtools_capture__.oct"; \
	else \
	  echo "devtools: no working compiler for __devtools_capture__.cc."; \
	  echo "devtools: the read-only server is unaffected; the evaluating server"; \
	  echo "devtools: will take a subprocess's output back and print it through"; \
	  echo "devtools: the interpreter instead of capturing it at the descriptor,"; \
	  echo "devtools: refusing only the two forms that cannot be taken back."; \
	  echo "devtools: Build log follows."; \
	  cat devtools_capture.log; \
	fi

guard:
	@if $(MKOCTFILE) __devtools_guard__.cc > devtools_guard.log 2>&1; then \
	  echo "devtools: built __devtools_guard__.oct"; \
	else \
	  echo "devtools: no working compiler for __devtools_guard__.cc."; \
	  echo "devtools: the evaluating server will run without a deadline, so code"; \
	  echo "devtools: that does not return holds it until the host restarts it."; \
	  cat devtools_guard.log; \
	fi

spawn:
	@if $(MKOCTFILE) __devtools_spawn__.cc > devtools_spawn.log 2>&1; then \
	  echo "devtools: built __devtools_spawn__.oct"; \
	else \
	  echo "devtools: no working compiler for __devtools_spawn__.cc."; \
	  echo "devtools: on Windows, devtools.mcpEval ('Sandbox') will refuse"; \
	  echo "devtools: every call, each needing a process of its own."; \
	  cat devtools_spawn.log; \
	fi

## A directory per dialect, named as the call names it, so that
## `__parse__ (TEXT, 'octave-strict')` and grammar/octave-strict are plainly the same
## thing.  Only Octave takes the qualifier, having the two modes; MATLAB has
## one and its bare name says so.  The parser is seven compilations and a link: the tree-sitter runtime,
## which its own lib.c gathers into one translation unit, the generated
## grammar, and the scanner beside it.  Vendored whole because pkg has no way
## to depend on a system libtree-sitter, and a user would not have one.
TS_RUNTIME = tree-sitter/src/lib.c
TS_INCLUDE = -Itree-sitter/include -Itree-sitter/src
TS_OBJS = ts_runtime.o \
  ts_octave.o ts_octave_scanner.o \
  ts_octave_strict.o ts_octave_strict_scanner.o \
  ts_matlab.o ts_matlab_scanner.o

parse:
	@if $(MKOCTFILE) -c $(TS_INCLUDE) $(TS_RUNTIME) -o ts_runtime.o \
	    > devtools_parse.log 2>&1 \
	  && $(MKOCTFILE) -c -Igrammar grammar/octave/parser.c -o ts_octave.o \
	    >> devtools_parse.log 2>&1 \
	  && $(MKOCTFILE) -c -Igrammar grammar/octave/scanner.c \
	    -o ts_octave_scanner.o >> devtools_parse.log 2>&1 \
	  && $(MKOCTFILE) -c -Igrammar grammar/octave-strict/parser.c \
	    -o ts_octave_strict.o >> devtools_parse.log 2>&1 \
	  && $(MKOCTFILE) -c -Igrammar grammar/octave-strict/scanner.c \
	    -o ts_octave_strict_scanner.o >> devtools_parse.log 2>&1 \
	  && $(MKOCTFILE) -c -Igrammar grammar/matlab/parser.c \
	    -o ts_matlab.o >> devtools_parse.log 2>&1 \
	  && $(MKOCTFILE) -c -Igrammar grammar/matlab/scanner.c \
	    -o ts_matlab_scanner.o >> devtools_parse.log 2>&1 \
	  && $(MKOCTFILE) -Itree-sitter/include __devtools_parse__.cc $(TS_OBJS) \
	    -o __devtools_parse__.oct >> devtools_parse.log 2>&1; then \
	  echo "devtools: built __devtools_parse__.oct"; \
	else \
	  echo "devtools: no working compiler for __devtools_parse__.cc."; \
	  echo "devtools: the servers are unaffected; what is lost is parsing"; \
	  echo "devtools: Octave source without running it, which the language"; \
	  echo "devtools: server and the dialect checks need."; \
	  echo "devtools: Build log follows."; \
	  cat devtools_parse.log; \
	fi

clean:
	-rm -f *.o *.oct devtools_capture.log devtools_guard.log \
	  devtools_spawn.log devtools_parse.log

.PHONY: all capture guard spawn parse clean
