## Copyright (C) 2026 Andreas Bertsatos <abertsatos@biol.uoa.gr>
##
## This file is part of the mcp package for GNU Octave.
##
## This program is free software; you can redistribute it and/or modify it under
## the terms of the GNU General Public License as published by the Free Software
## Foundation; either version 3 of the License, or (at your option) any later
## version.
##
## This program is distributed in the hope that it will be useful, but WITHOUT
## ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
## FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
## details.
##
## You should have received a copy of the GNU General Public License along with
## this program; if not, see <http://www.gnu.org/licenses/>.

## -*- texinfo -*-
## @deftypefn  {mcp} {@var{R} =} mcp.jsonrpcError (@var{ID}, @var{CODE}, @var{MSG})
## @deftypefnx {mcp} {@var{R} =} mcp.jsonrpcError (@var{ID}, @var{CODE}, @var{MSG}, @var{DATA})
##
## Build a JSON-RPC error response.
##
## @code{@var{R} = mcp.jsonrpcError (@var{ID}, @var{CODE}, @var{MSG})} returns
## the scalar structure of an error response carrying the integer @var{CODE} and
## the character vector @var{MSG}.  @var{ID} is the identifier of the request
## being answered, either a character vector or a numeric scalar.  Pass an empty
## value to omit the field, which is correct only when the identifier could not
## be read from a malformed request.
##
## @code{@var{R} = mcp.jsonrpcError (@dots{}, @var{DATA})} adds a @code{data}
## member.  @var{DATA} may be any value @code{jsonencode} accepts, and carries
## the machine-readable part of the failure: the versions a server supports, the
## name of a missing field, and so on.
##
## The fields are inserted in wire order, @code{jsonrpc} then @code{id} then
## @code{error}, because @code{jsonencode} preserves the order in which the
## fields of a structure were created.
##
## The result is a structure and not text.  Pass it to
## @code{mcp.encodeResponse} to obtain the line that goes on the wire.
## @end deftypefn

function R = jsonrpcError (ID, CODE, MSG, DATA)

  ## Input validation
  if (nargin < 3 || nargin > 4)
    error ("mcp.jsonrpcError: invalid number of input arguments.");
  endif
  if (! (isempty (ID) || (ischar (ID) && isrow (ID)) ...
                      || (isnumeric (ID) && isscalar (ID))))
    error (strcat ("mcp.jsonrpcError: ID must be a character vector,", ...
                   " a numeric scalar, or empty to omit the field."));
  endif
  if (! (isnumeric (CODE) && isscalar (CODE) && CODE == fix (CODE)))
    error ("mcp.jsonrpcError: CODE must be an integer scalar.");
  endif
  if (! (ischar (MSG) && isrow (MSG)))
    error ("mcp.jsonrpcError: MSG must be a character vector.");
  endif

  R = struct ("jsonrpc", "2.0");
  if (! isempty (ID))
    R.id = ID;
  endif
  E = struct ("code", CODE, "message", MSG);
  if (nargin > 3)
    E.data = DATA;
  endif
  R.error = E;

endfunction

%!test
%! R = mcp.jsonrpcError (1, -32601, "Method not found");
%! assert_equal (fieldnames (R), {'jsonrpc'; 'id'; 'error'});
%! assert_equal (R.jsonrpc, "2.0");
%! assert_equal (R.id, 1);
%! assert_equal (R.error.code, -32601);
%! assert_equal (R.error.message, "Method not found");
%! assert_equal (isfield (R.error, "data"), false);

%!test
%! ## A string identifier stays a string, so the client can correlate it.
%! R = mcp.jsonrpcError ("abc", -32700, "Parse error");
%! assert_equal (R.id, "abc");
%! assert_equal (class (R.id), "char");

%!test
%! ## An empty identifier omits the field, which is the malformed-request case.
%! R = mcp.jsonrpcError ([], -32700, "Parse error");
%! assert_equal (fieldnames (R), {'jsonrpc'; 'error'});

%!test
%! D = struct ("supported", {{'2026-07-28'}}, "requested", "1900-01-01");
%! R = mcp.jsonrpcError (2, -32022, "Unsupported protocol version", D);
%! assert_equal (R.error.data.requested, "1900-01-01");
%! assert_equal (R.error.data.supported, {'2026-07-28'});

%!error <mcp\.jsonrpcError: invalid number of input arguments\.> ...
%! mcp.jsonrpcError (1, -1)
%!error <mcp\.jsonrpcError: ID must be a character vector, a numeric scalar, or empty to omit the field\.> ...
%! mcp.jsonrpcError (struct (), -1, "a")
%!error <mcp\.jsonrpcError: CODE must be an integer scalar\.> ...
%! mcp.jsonrpcError (1, -1.5, "a")
%!error <mcp\.jsonrpcError: CODE must be an integer scalar\.> ...
%! mcp.jsonrpcError (1, [-1, -2], "a")
%!error <mcp\.jsonrpcError: MSG must be a character vector\.> ...
%! mcp.jsonrpcError (1, -1, 5)
