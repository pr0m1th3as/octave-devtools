## Part of the mcp package: a shadow that stands in front of a core function
## while mcp.serveEval evaluates code.  See mcp.serveEval for why.
function keyboard (varargin)
  error (strcat ("keyboard: this server has no terminal, so a debug prompt", ...
                 " would wait for a reply that cannot come."));
endfunction
