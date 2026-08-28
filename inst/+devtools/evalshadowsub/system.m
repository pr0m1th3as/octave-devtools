## Part of the devtools package: a shadow that stands in front of a core function
## while devtools.mcpEval evaluates code, and only where this installation has no
## __devtools_capture__ to hold descriptor 1.  See devtools.mcpEval for why.
##
## Core lets the child inherit descriptor 1 only when the output is not being
## returned, so asking for it back is the whole containment.  What the caller
## did not want returned is written through the interpreter instead, where
## evalc takes it as it takes a printf.  Measured: with the output returned
## nothing escapes evalc, and without it the child writes past evalc entirely.
##
## Refusing the call outright, which this did before, refused every safe form
## with it, core's own copyfile, movefile, ls, tar and unpack among them, since
## all of them ask for the output back.
function varargout = system (varargin)

  if (numel (varargin) < 1 || numel (varargin) > 3)
    error ("Invalid call to system.");
  endif

  ## The one form that cannot be contained: core refuses to return the output
  ## of an asynchronous command at all, so its child keeps descriptor 1.
  if (numel (varargin) > 2 && ischar (varargin{3}) ...
      && strcmpi (strtrim (varargin{3}), 'async'))
    error (strcat ("system: this server was installed without its output", ...
                   " capture, and the output of an asynchronous command", ...
                   " cannot be captured, so it would write into the stream", ...
                   " that carries the protocol. Run it synchronously, or", ...
                   " rebuild the package with a working compiler."));
  endif

  ## Core's own rule for where the output goes, kept so that a caller cannot
  ## tell this apart from the real thing by the shape of what comes back.
  if (numel (varargin) > 1)
    ret = varargin{2};
    if (! (isscalar (ret) && (islogical (ret) || isnumeric (ret)) ...
           && (ret == 0 || ret == 1)))
      error ("system: RETURN_OUTPUT must be boolean value true or false");
    endif
  else
    ret = (nargout > 1);
  endif

  [status, text] = builtin ("system", varargin{1}, true);

  if (! ret)
    puts (text);
  endif

  varargout{1} = status;
  if (ret && nargout > 1)
    varargout{2} = text;
  endif

endfunction
