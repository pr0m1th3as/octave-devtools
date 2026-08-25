## Makefile for the mcp package.
##
## The build must never fail.  mcp.serve needs nothing from here, and a machine
## with no working compiler must still install the package and use the
## read-only server; what it loses is the output capture the evaluating server
## uses, and mcp.serveEval says so rather than misbehaving.

MKOCTFILE ?= mkoctfile

all: capture

capture:
	@if $(MKOCTFILE) __mcp_capture__.cc > mcp_build.log 2>&1; then \
	  echo "mcp: built __mcp_capture__.oct"; \
	else \
	  echo "mcp: no working compiler for __mcp_capture__.cc."; \
	  echo "mcp: the read-only server is unaffected; the evaluating server"; \
	  echo "mcp: will refuse subprocess-spawning functions instead of"; \
	  echo "mcp: capturing what they print.  Build log follows."; \
	  cat mcp_build.log; \
	fi

clean:
	-rm -f *.o *.oct mcp_build.log

.PHONY: all capture clean
