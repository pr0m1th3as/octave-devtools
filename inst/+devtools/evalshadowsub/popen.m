## Part of the devtools package: a shadow that stands in front of a core function
## while devtools.mcpEval evaluates code, and only where this installation has no
## __devtools_capture__ to hold descriptor 1.  See devtools.mcpEval for why.
##
## Mode "r" pipes the child's output, which then never reaches the stream, so
## it is passed through.  Mode "w" leaves the child holding descriptor 1 and
## there is nothing here that could read what it writes, so it is the one form
## this installation refuses.  Measured under evalc, both ways.
function varargout = popen (varargin)

  if (numel (varargin) != 2)
    error ("Invalid call to popen.");
  endif

  if (ischar (varargin{2}) && any (varargin{2} == 'w'))
    error (strcat ("popen: this server was installed without its output", ...
                   " capture, so a subprocess opened for writing would", ...
                   " write into the stream that carries the protocol.", ...
                   " Open it for reading instead, or run the command with", ...
                   " system and take its output back."));
  endif

  varargout{1} = builtin ("popen", varargin{:});

endfunction
