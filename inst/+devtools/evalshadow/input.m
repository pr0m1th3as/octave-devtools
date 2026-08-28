## Part of the devtools package: a shadow that stands in front of a core function
## while devtools.mcpEval evaluates code.  See devtools.mcpEval for why.
function varargout = input (varargin)
  error (strcat ("input: this server has no terminal, so a prompt would", ...
                 " wait for a reply that cannot come. Ask for the value in", ...
                 " the code instead."));
endfunction
