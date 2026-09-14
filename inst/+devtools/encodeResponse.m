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
## @deftypefn {devtools} {@var{TXT} =} devtools.encodeResponse (@var{R})
##
## Encode a response structure into the line that goes on the wire.
##
## @code{@var{TXT} = devtools.encodeResponse (@var{R})} returns the character vector
## carrying the scalar structure @var{R} as one newline-delimited JSON-RPC
## message.  The newline itself is not included: the caller appends it, because
## the caller is what knows it is writing to a stream.
##
## Two things happen here that @code{jsonencode} alone does not do.
##
## The reserved metadata keys of this protocol are restored.  A key such as
## @code{io.modelcontextprotocol/serverInfo} is not a valid Octave identifier,
## so it cannot be the name of a structure field; @code{jsondecode} mangles the
## dot and the slash to underscores on the way in, and @code{jsonencode} would
## faithfully emit the mangled name on the way out.  Build such a field as
## @code{io_modelcontextprotocol_serverInfo} and it is restored here, and this
## package's own key @code{io.github.pr0m1th3as.devtools/sandbox} is built as
## @code{io_github_pr0m1th3as_devtools_sandbox} and restored the same way.  The
## substitution is anchored to key position, on the quote and colon that only a
## key can carry, so a @emph{value} that happens to contain the same text is
## left alone.
##
## The framing invariant is checked.  A message must not contain an embedded
## newline, since a newline is what separates one message from the next, and a
## single stray one desynchronises the stream for the rest of the session.
## @code{jsonencode} escapes control characters and so cannot produce one, which
## makes this a guard against a defect here rather than against ordinary data.
## @end deftypefn

function TXT = encodeResponse (R)

  ## Input validation
  if (nargin != 1)
    error ("devtools.encodeResponse: invalid number of input arguments.");
  endif
  if (! (isstruct (R) && isscalar (R)))
    error ("devtools.encodeResponse: R must be a scalar structure.");
  endif
  if (! isfield (R, "jsonrpc"))
    error ("devtools.encodeResponse: R must have a jsonrpc field.");
  endif

  TXT = jsonencode (R);

  ## Restore the reserved keys, in key position only
  TXT = regexprep (TXT, '"io_modelcontextprotocol_([A-Za-z0-9]+)":', ...
                        '"io.modelcontextprotocol/$1":');
  TXT = regexprep (TXT, '"io_github_pr0m1th3as_devtools_([A-Za-z0-9]+)":', ...
                        '"io.github.pr0m1th3as.devtools/$1":');

  if (any (TXT == "\n" | TXT == "\r"))
    error (strcat ("devtools.encodeResponse: encoded message contains an", ...
                   " embedded newline, which would desynchronise the stream."));
  endif

endfunction

%!test
%! R = struct ("jsonrpc", "2.0", "id", 1, "result", struct ("resultType", "complete"));
%! assert_equal (devtools.encodeResponse (R), ...
%!               '{"jsonrpc":"2.0","id":1,"result":{"resultType":"complete"}}');

%!test
%! ## Field creation order is wire order, so the identifier follows the version.
%! R = struct ("jsonrpc", "2.0", "id", "a", "error", struct ("code", -1, "message", "m"));
%! assert_equal (devtools.encodeResponse (R), ...
%!               '{"jsonrpc":"2.0","id":"a","error":{"code":-1,"message":"m"}}');

%!test
%! ## A reserved metadata key is restored from the name a field can carry.
%! M = struct ("io_modelcontextprotocol_serverInfo", ...
%!             struct ("name", "devtools", "version", "0.1.0"));
%! R = struct ("jsonrpc", "2.0", "id", 1, "result", struct ("_meta", M));
%! T = devtools.encodeResponse (R);
%! assert_equal (! isempty (strfind (T, '"io.modelcontextprotocol/serverInfo":')), true);
%! assert_equal (isempty (strfind (T, "io_modelcontextprotocol")), true);

%!test
%! ## This package's own metadata key is restored the same way.
%! M = struct ("io_github_pr0m1th3as_devtools_sandbox", true);
%! R = struct ("jsonrpc", "2.0", "id", 1, "result", struct ("_meta", M));
%! assert_equal (devtools.encodeResponse (R), ...
%!   ['{"jsonrpc":"2.0","id":1,"result":{"_meta":', ...
%!    '{"io.github.pr0m1th3as.devtools/sandbox":true}}}']);

%!test
%! ## A value carrying the same text is not a key and must survive untouched.
%! R = struct ("jsonrpc", "2.0", "id", 1, ...
%!             "result", struct ("t", "io_modelcontextprotocol_serverInfo"));
%! T = devtools.encodeResponse (R);
%! assert_equal (T, ...
%!   '{"jsonrpc":"2.0","id":1,"result":{"t":"io_modelcontextprotocol_serverInfo"}}');

%!test
%! ## Text with newlines and quotes is escaped, never emitted raw.
%! txt = sprintf ("a\nb\t\"c\"\\d\r");
%! R = struct ("jsonrpc", "2.0", "id", 1, "result", struct ("text", txt));
%! T = devtools.encodeResponse (R);
%! assert_equal (any (T == "\n" | T == "\r"), false);
%! assert_equal (jsondecode (T).result.text, txt);

%!test
%! ## An array of content blocks must be a cell: a 1-by-1 struct array would
%! ## encode as a bare object and the client would reject the result.
%! res = struct ();
%! res.content = {struct("type", "text", "text", "hi")};
%! R = struct ("jsonrpc", "2.0", "id", 1);
%! R.result = res;
%! assert_equal (devtools.encodeResponse (R), ...
%!   '{"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"hi"}]}}');

%!test
%! ## An empty structure is the empty JSON object that capabilities need.
%! R = struct ("jsonrpc", "2.0", "id", 1, ...
%!             "result", struct ("capabilities", struct ("tools", struct ())));
%! assert_equal (devtools.encodeResponse (R), ...
%!   '{"jsonrpc":"2.0","id":1,"result":{"capabilities":{"tools":{}}}}');

%!error <devtools\.encodeResponse: invalid number of input arguments\.> ...
%! devtools.encodeResponse ()
%!error <devtools\.encodeResponse: R must be a scalar structure\.> ...
%! devtools.encodeResponse (5)
%!error <devtools\.encodeResponse: R must be a scalar structure\.> ...
%! devtools.encodeResponse (struct ("jsonrpc", {"2.0", "2.0"}))
%!error <devtools\.encodeResponse: R must have a jsonrpc field\.> ...
%! devtools.encodeResponse (struct ("id", 1))
