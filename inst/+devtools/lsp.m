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
## @deftypefn {devtools} {} devtools.lsp ()
##
## Serve the Language Server Protocol on standard input and output.
##
## @code{devtools.lsp ()} reads Language Server Protocol messages from standard
## input, answers each one, and writes the answer to standard output.  It
## returns when standard input reaches end of file, and ends the process on an
## @code{exit} notification, with status 0 after @code{shutdown} and 1
## without, as the protocol asks.  It is the entry point an editor launches;
## it is not meant to be called at an interactive prompt, where it would take
## the terminal.
##
## Five features are served:
##
## @table @asis
## @item hover
## the help of the name under the cursor, as @code{help} renders it;
##
## @item go to definition
## the file and line that define it;
##
## @item document symbols
## the outline of a file: its class, properties, methods and functions;
##
## @item workspace symbols
## the functions, classes and methods of the project, by part of their name;
##
## @item completion
## function, keyword and project names, a namespace's contents after its name
## and a dot, and a class's methods and properties after an object and a dot.
## @end table
##
## The answers come from the interpreter serving them, so they are what this
## Octave, with these packages loaded, would itself say.  The folder the editor
## opens is the project.  Its functions and classes are read from its files and
## never put on the load path, since adding a folder to the path runs its
## @file{PKG_ADD}; where the project and a loaded package both define a name,
## the project's definition is the one answered, the installed copy of a
## package under development being the stale one.
##
## A method that several classes define is answered only where the class is
## certain: a call written @code{Class.method}, or a method or property used on
## the object of the method being edited, such as @code{predict (obj, X)} or
## @code{obj.X} inside a method whose first parameter is @code{obj}.
## Otherwise hover lists every definition and go to definition offers each.
## A name's meaning is otherwise settled only at run time, so there are no
## diagnostics and no rename.
##
## This server evaluates no code, runs no user function, and writes nothing.
## Configure an editor to launch it with:
##
## @example
## octave-cli -q --no-init-file --eval "pkg load devtools; devtools.lsp ()"
## @end example
##
## @strong{Do not shorten that command.}  @code{--no-init-file} skips
## @file{~/.octaverc}, whose output would arrive before this function exists
## and corrupt the stream, as for @code{devtools.mcp}.  On Windows, name
## @file{octave-cli.exe} in full.  The server sees the packages its command
## loads and no others, so name the ones the project uses:
##
## @example
## --eval "pkg load devtools statistics datatypes; devtools.lsp ()"
## @end example
##
## For Kate, enable the LSP Client plugin and add to its User Server Settings:
##
## @example
## @group
## @{
##   "servers": @{
##     "octave": @{
##       "command": ["octave-cli", "-q", "--no-init-file", "--eval",
##                   "pkg load devtools; devtools.lsp ()"],
##       "rootIndicationFileNames": ["DESCRIPTION", ".git"],
##       "highlightingModeRegex": "^(Octave|Matlab)$"
##     @}
##   @}
## @}
## @end group
## @end example
##
## Kate may take a @file{.m} file for Objective-C and start its server for
## that language instead; set the file's highlighting to Octave, or give the
## Octave file type the higher priority for @file{*.m}.
##
## For Neovim 0.11 and later, in @file{init.lua}:
##
## @example
## @group
## vim.lsp.config ('octave', @{
##   cmd = @{'octave-cli', '-q', '--no-init-file', '--eval',
##          'pkg load devtools; devtools.lsp ()'@},
##   filetypes = @{'octave', 'matlab'@},
##   root_markers = @{'DESCRIPTION', '.git'@},
## @})
## vim.lsp.enable ('octave')
## @end group
## @end example
##
## For Emacs with Eglot, in @file{init.el}; the first line stops Emacs taking
## a @file{.m} file for Objective-C:
##
## @example
## @group
## (add-to-list 'auto-mode-alist '("\\.m\\'" . octave-mode))
## (with-eval-after-load 'eglot
##   (add-to-list 'eglot-server-programs
##                '(octave-mode . ("octave-cli" "-q" "--no-init-file" "--eval"
##                                 "pkg load devtools; devtools.lsp ()"))))
## @end group
## @end example
##
## Everything diagnostic goes to standard error.
##
## @seealso{devtools.mcp}
## @end deftypefn

function lsp ()

  logmsg ("listening, pid %d", getpid ());
  S = [];
  while (true)

    body = readMessage ();
    if (! ischar (body))
      break;                          # end of input
    endif

    REPLIES = {};
    R = [];
    try
      R = devtools.decodeRequest (body);
      [REPLIES, S] = devtools.__lspDispatch__ (R, S);
    catch err
      logmsg ("internal error: %s", err.message);
      if (isstruct (R) && isfield (R, "hasid") && R.hasid ...
          && strcmp (R.type, 'request'))
        REPLIES = {devtools.jsonrpcError(R.id, -32603, "Internal error")};
      endif
    end_try_catch

    for ii = 1:numel (REPLIES)
      writeMessage (jsonencode (REPLIES{ii}));
    endfor

    if (isstruct (S) && S.exit)
      logmsg ("exit");
      exit (S.exitCode);
    endif

  endwhile

  logmsg ("end of input, exiting");

endfunction

function body = readMessage ()

  ## The headers a byte at a time, since fgetl blocks on a pipe until the
  ## writer closes it; the body in one read, fread of a count returning as
  ## soon as that many bytes have arrived.
  body = -1;
  len = -1;
  while (true)
    line = readHeaderLine ();
    if (! ischar (line))
      return;
    endif
    if (isempty (line))
      if (len >= 0)
        break;
      endif
      continue;                       # a stray blank line before a header
    endif
    tok = regexp (line, '^Content-Length:\s*(\d+)\s*$', 'tokens', 'once', ...
                  'ignorecase');
    if (! isempty (tok))
      len = str2double (tok{1});
    endif
  endwhile
  body = fread (stdin, len, "uint8=>char")';
  if (numel (body) < len)
    body = -1;                        # end of input inside a message
  elseif (isempty (body))
    body = '';
  endif

endfunction

function L = readHeaderLine ()
  buf = zeros (1, 256, "uint8");
  n = 0;
  while (true)
    c = fread (stdin, 1, "uint8");
    if (isempty (c))
      L = -1;
      return;
    endif
    if (c == 10)
      L = char (buf(1:n));
      return;
    endif
    if (c != 13)
      n++;
      if (n > numel (buf))
        buf = [buf, zeros(1, numel (buf), "uint8")];
      endif
      buf(n) = c;
    endif
  endwhile
endfunction

function writeMessage (body)
  ## An Octave char is a byte, so numel counts what Content-Length counts
  fputs (stdout, sprintf ("Content-Length: %d\r\n\r\n", numel (body)));
  fputs (stdout, body);
  fflush (stdout);
endfunction

function logmsg (fmt, varargin)
  fputs (stderr, ["devtools.lsp: " sprintf(fmt, varargin{:}) "\n"]);
  fflush (stderr);
endfunction

%!function s = nullDevice ()
%!  if (ispc ())
%!    s = "NUL";
%!  else
%!    s = "/dev/null";
%!  endif
%!endfunction

%!test
%! ## The one test no offline test can replace: run the real server as a
%! ## subprocess and prove that every byte it wrote to stdout was a message.
%! if (exist ("__devtools_parse__", "file") != 3)
%!   return;
%! endif
%! octcli = fullfile (OCTAVE_HOME (), "bin", "octave-cli");
%! if (ispc ())
%!   octcli = [octcli ".exe"];
%! endif
%! if (! isfile (octcli))
%!   return;
%! endif
%! msgs = {'{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}', ...
%!         '{"jsonrpc":"2.0","method":"initialized","params":{}}', ...
%!         '{"jsonrpc":"2.0","id":2,"method":"shutdown"}', ...
%!         '{"jsonrpc":"2.0","method":"exit"}'};
%! in = [tempname() ".txt"];
%! fid = fopen (in, "w");
%! for ii = 1:numel (msgs)
%!   fprintf (fid, "Content-Length: %d\r\n\r\n%s", numel (msgs{ii}), msgs{ii});
%! endfor
%! fclose (fid);
%! instdir = fileparts (fileparts (which ("devtools.lsp")));
%! octdir = fileparts (which ("__devtools_parse__"));
%! code = sprintf ("addpath ('%s'); addpath ('%s'); devtools.lsp ()", ...
%!                 instdir, octdir);
%! out = [tempname() ".txt"];
%! cmd = '"%s" -q --no-init-file --eval "%s" < "%s" > "%s" 2>%s';
%! st = system (sprintf (cmd, octcli, code, in, out, nullDevice ()));
%! txt = fileread (out);
%! delete (in);
%! delete (out);
%! ## Every byte is a frame, and the two requests are answered in order
%! ids = [];
%! while (! isempty (txt))
%!   tok = regexp (txt, '^Content-Length: (\d+)\r\n\r\n', 'tokens', 'once');
%!   assert_equal (isempty (tok), false);
%!   n = str2double (tok{1});
%!   head = numel (sprintf ("Content-Length: %d\r\n\r\n", n));
%!   J = jsondecode (txt(head+1:head+n));
%!   ids(end+1) = J.id;
%!   txt = txt(head+n+1:end);
%! endwhile
%! assert_equal (ids, [1, 2]);
%! assert_equal (st, 0);
