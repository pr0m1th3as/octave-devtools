## Part of the devtools package: a shadow that stands in front of a core function
## while devtools.mcpEval evaluates code.  See devtools.mcpEval for why.
function keyboard (varargin)
  error (strcat ("keyboard: this server has no terminal, so a debug prompt", ...
                 " would wait for a reply that cannot come."));
endfunction
