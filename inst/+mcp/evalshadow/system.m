## Part of the mcp package: a shadow that stands in front of a core function
## while mcp.serveEval evaluates code.  See mcp.serveEval for why.
function varargout = system (varargin)
  error (strcat ("system: a subprocess writes past this server's output", ...
                 " capture and into the protocol stream, so it is refused", ...
                 " while the server is evaluating."));
endfunction
