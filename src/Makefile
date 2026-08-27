## Makefile for the mcp package.
##
## The build must never fail.  mcp.serve needs nothing from here, and a machine
## with no working compiler must still install the package and use the
## read-only server; what it loses is the output capture the evaluating server
## uses, and mcp.serveEval says so rather than misbehaving.

MKOCTFILE ?= mkoctfile

all: capture guard

capture:
	@if $(MKOCTFILE) __mcp_capture__.cc > mcp_build.log 2>&1; then \
	  echo "mcp: built __mcp_capture__.oct"; \
	else \
	  echo "mcp: no working compiler for __mcp_capture__.cc."; \
	  echo "mcp: the read-only server is unaffected; the evaluating server"; \
	  echo "mcp: will take a subprocess's output back and print it through"; \
	  echo "mcp: the interpreter instead of capturing it at the descriptor,"; \
	  echo "mcp: refusing only the two forms that cannot be taken back."; \
	  echo "mcp: Build log follows."; \
	  cat mcp_build.log; \
	fi

guard:
	@if $(MKOCTFILE) __mcp_guard__.cc > mcp_build.log 2>&1; then \
	  echo "mcp: built __mcp_guard__.oct"; \
	else \
	  echo "mcp: no working compiler for __mcp_guard__.cc."; \
	  echo "mcp: the evaluating server will run without a deadline, so code"; \
	  echo "mcp: that does not return holds it until the host restarts it."; \
	  cat mcp_build.log; \
	fi

clean:
	-rm -f *.o *.oct mcp_build.log

.PHONY: all capture guard clean
