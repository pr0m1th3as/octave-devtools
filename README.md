# mcp

A [Model Context Protocol](https://modelcontextprotocol.io) server that exposes
GNU Octave to any MCP-capable assistant.

**Status: pre-release. Nothing is implemented yet.** The design is settled and
recorded in `../OCTAVE_MCP_PLAN.md`; this README describes what the first
release will provide.

## What it is

The server process *is* an Octave interpreter. There is no wrapper process and
no second copy of the truth: the interpreter answering "what does `kmeans` do"
is the interpreter being asked about, with the same load path, the same
installed packages and the same version.

The first release provides read-only introspection only. It **evaluates no
code, runs no user function, and writes nothing**, which is what makes it safe
to grant blanket permission to.

## Requirements

GNU Octave 11.1.0 or later.

## Installation

```
pkg install mcp
```

## Configuration

Add the server to your MCP host's configuration:

```json
{
  "mcpServers": {
    "octave": {
      "command": "octave-cli",
      "args": ["-q", "--no-init-file", "--eval", "pkg load mcp; mcp.serve ()"]
    }
  }
}
```

**Do not shorten that command line.** `-q` and `--no-init-file` are
correctness requirements, not tidiness:

- `-q` suppresses the startup banner, which is written to standard output.
- `--no-init-file` skips `~/.octaverc`, which may print, and whose output is
  also written to standard output.

The server communicates over standard output, so anything else written there
corrupts the stream. Both of these happen before `mcp.serve` starts running,
so the server cannot undo them. A corrupted stream usually appears in the host
as an unexplained connection failure.

To check a configuration before blaming the host, run

```
mcp.selftest ()
```

which starts the server exactly as configured above, completes a handshake, and
reports whether standard output was clean, naming the offending first line if
it was not.

## Tools

| Tool | Answers |
|------|---------|
| `octave_help` | the help text for a function, class, method or operator |
| `octave_which` | where a name resolves, what kind of thing it is, and which package owns it |
| `octave_search` | which functions match a description, when the name is not known |
| `octave_pkg` | which packages are installed, at which versions, and which are loaded |

Static context is served as resources rather than tools: `octave://version`,
`octave://path` and `octave://packages`.

## License

GPLv3 or later. See `COPYING`.
