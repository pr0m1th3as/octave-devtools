## Copyright (C) 2026 Andreas Bertsatos <abertsatos@biol.uoa.gr>
##
## This file is part of the devtools package for GNU Octave.
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
## @deftypefn {devtools} {@var{R} =} devtools.decodeRequest (@var{TXT})
##
## Decode one line of the wire into a request structure.
##
## @code{@var{R} = devtools.decodeRequest (@var{TXT})} parses the character vector
## @var{TXT}, one newline-delimited JSON-RPC message as the stdio transport
## frames it, and returns a scalar structure describing what was received.  It
## never raises for anything the peer sent; a peer can only produce a structure
## whose @code{type} is @qcode{"invalid"}.  It raises only when called wrongly.
##
## The returned structure always carries these fields:
##
## @table @code
## @item type
## One of @qcode{"request"}, @qcode{"notification"}, @qcode{"blank"} or
## @qcode{"invalid"}.  A request expects a response, a notification must never
## be answered, a blank line is ignored, and an invalid line is answered with
## the error described by @code{code} and @code{message}.
##
## @item method
## The method name, or the empty character vector when none was read.
##
## @item params
## The @code{params} member as a scalar structure, or an empty structure when
## the message carried none.
##
## @item hasid
## True when an identifier was read.  An identifier may be recovered even from
## an invalid message, and the error must then carry it.
##
## @item id
## The identifier, preserving the type it arrived as.  A JSON string decodes to
## a character vector and a JSON number to a double, and echoing the wrong one
## back breaks the client's correlation of responses to requests.
##
## @item code
## @itemx message
## The JSON-RPC error to answer with, meaningful only when @code{type} is
## @qcode{"invalid"}: @math{-32700} for text that is not JSON, @math{-32600}
## for JSON that is not a well-formed JSON-RPC message.
## @end table
##
## A message is well formed when it is a JSON object whose @code{jsonrpc} member
## is @qcode{"2.0"} and whose @code{method} member is a string.  An identifier
## that is present but is neither a string nor a numeric scalar is rejected,
## which includes @code{null}: unlike base JSON-RPC, this protocol forbids it.
## @end deftypefn

function R = decodeRequest (TXT)

  ## Input validation
  if (nargin != 1)
    error ("devtools.decodeRequest: invalid number of input arguments.");
  endif
  if (! (ischar (TXT) && (isrow (TXT) || isempty (TXT))))
    error ("devtools.decodeRequest: TXT must be a character vector.");
  endif

  R = struct ("type", "invalid", "method", "", "params", struct (), ...
              "hasid", false, "id", [], "code", -32600, ...
              "message", "Invalid Request");

  if (isempty (strtrim (TXT)))
    R.type = "blank";
    R.code = 0;
    R.message = "";
    return;
  endif

  ## Anything the peer can send must come back as a structure, never an error
  try
    J = jsondecode (TXT);
  catch
    R.code = -32700;
    R.message = "Parse error";
    return;
  end_try_catch

  if (! (isstruct (J) && isscalar (J)))
    return;
  endif
  if (! (isfield (J, "jsonrpc") && ischar (J.jsonrpc) ...
                                && strcmp (J.jsonrpc, "2.0")))
    return;
  endif

  ## Read the identifier before validating the rest, so that an error over a
  ## malformed request can still be correlated by the client
  if (isfield (J, "id"))
    if (! ((ischar (J.id) && isrow (J.id)) ...
           || (isnumeric (J.id) && isscalar (J.id))))
      return;
    endif
    R.hasid = true;
    R.id = J.id;
  endif

  if (! (isfield (J, "method") && ischar (J.method) && isrow (J.method)))
    return;
  endif
  R.method = J.method;

  if (isfield (J, "params") && isstruct (J.params) && isscalar (J.params))
    R.params = J.params;
  endif

  if (R.hasid)
    R.type = "request";
  else
    R.type = "notification";
  endif
  R.code = 0;
  R.message = "";

endfunction

%!test
%! R = devtools.decodeRequest ('{"jsonrpc":"2.0","id":1,"method":"tools/list"}');
%! assert_equal (R.type, "request");
%! assert_equal (R.method, "tools/list");
%! assert_equal (R.id, 1);
%! assert_equal (R.hasid, true);

%!test
%! ## A string identifier must stay a string all the way back out.
%! R = devtools.decodeRequest ('{"jsonrpc":"2.0","id":"a1","method":"ping"}');
%! assert_equal (R.id, "a1");
%! assert_equal (class (R.id), "char");

%!test
%! ## No identifier means a notification, which is never answered.
%! R = devtools.decodeRequest ('{"jsonrpc":"2.0","method":"notifications/cancelled"}');
%! assert_equal (R.type, "notification");
%! assert_equal (R.hasid, false);

%!test
%! R = devtools.decodeRequest ('{"jsonrpc":"2.0","id":1,"method":"m","params":{"a":5}}');
%! assert_equal (R.params.a, 5);

%!test
%! ## A message with no params still yields a structure, so callers need no guard.
%! R = devtools.decodeRequest ('{"jsonrpc":"2.0","id":1,"method":"m"}');
%! assert_equal (isstruct (R.params), true);
%! assert_equal (isempty (fieldnames (R.params)), true);

%!test
%! ## The keys of _meta are not valid identifiers and jsondecode mangles them.
%! txt = ['{"jsonrpc":"2.0","id":1,"method":"m","params":{"_meta":', ...
%!        '{"io.modelcontextprotocol/protocolVersion":"2026-07-28"}}}'];
%! R = devtools.decodeRequest (txt);
%! assert_equal (R.params._meta.io_modelcontextprotocol_protocolVersion, ...
%!               "2026-07-28");

%!test
%! R = devtools.decodeRequest ("not json at all");
%! assert_equal (R.type, "invalid");
%! assert_equal (R.code, -32700);
%! assert_equal (R.message, "Parse error");

%!test
%! R = devtools.decodeRequest ('{"jsonrpc":"1.0","id":1,"method":"m"}');
%! assert_equal (R.type, "invalid");
%! assert_equal (R.code, -32600);

%!test
%! ## An identifier read from an otherwise invalid message is still reported.
%! R = devtools.decodeRequest ('{"jsonrpc":"2.0","id":7}');
%! assert_equal (R.type, "invalid");
%! assert_equal (R.hasid, true);
%! assert_equal (R.id, 7);

%!test
%! ## A null identifier is forbidden by this protocol, unlike base JSON-RPC.
%! R = devtools.decodeRequest ('{"jsonrpc":"2.0","id":null,"method":"m"}');
%! assert_equal (R.type, "invalid");
%! assert_equal (R.hasid, false);

%!test
%! R = devtools.decodeRequest ('[1,2,3]');
%! assert_equal (R.type, "invalid");
%! assert_equal (R.code, -32600);

%!test
%! ## A namespaced call cannot be indexed directly, hence the variables.
%! A = devtools.decodeRequest ("");
%! B = devtools.decodeRequest ("   ");
%! assert_equal (A.type, "blank");
%! assert_equal (B.type, "blank");

%!error <devtools\.decodeRequest: invalid number of input arguments\.> ...
%! devtools.decodeRequest ()
%!error <devtools\.decodeRequest: TXT must be a character vector\.> ...
%! devtools.decodeRequest (5)
%!error <devtools\.decodeRequest: TXT must be a character vector\.> ...
%! devtools.decodeRequest (["ab"; "cd"])
