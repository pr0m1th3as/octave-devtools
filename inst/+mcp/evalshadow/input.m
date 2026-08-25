## Part of the mcp package: a shadow that stands in front of a core function
## while mcp.serveEval evaluates code.  See mcp.serveEval for why.
function varargout = input (varargin)
  error (strcat ("input: this server has no terminal, so a prompt would", ...
                 " wait for a reply that cannot come. Ask for the value in", ...
                 " the code instead."));
endfunction
