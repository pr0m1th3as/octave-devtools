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
## @deftypefn {devtools} {} devtools.mcp ()
##
## Serve the Model Context Protocol on standard input and output.
##
## @code{devtools.mcp ()} reads newline-delimited JSON-RPC messages from
## standard input, answers each one, writes the answer to standard output, and
## returns only when standard input reaches end of file.  It is the entry point
## a host launches; it is not meant to be called at an interactive prompt, where
## it would take the terminal.
##
## Both protocol eras are served.  A client that opens with per-request metadata
## is answered under revision 2026-07-28 and statelessly; a client that opens
## with an @code{initialize} handshake is answered under revision 2025-11-25 for
## the life of the process.  The choice is made by the first request and the
## tools are the same in either case.
##
## The read-only tool set is served here.  This server evaluates no code, runs
## no user function, and writes nothing, which is the property that lets a user
## grant it blanket permission.  Evaluation lives behind a separate entry point
## and a separate configuration entry, so that it cannot be reached by a host
## configured for this one.
##
## Configure a host to launch it with:
##
## @example
## octave-cli -q --no-init-file --eval "pkg load devtools; devtools.mcp ()"
## @end example
##
## @strong{Do not shorten that command.}  @code{--no-init-file} is the
## load-bearing flag: it skips @file{~/.octaverc}, whose output would arrive
## before this function exists, and a single byte written there corrupts the
## stream for the whole session.  Measured on 11.2.0, @code{--eval} already
## makes the run non-interactive so that no banner is written either way and
## @code{-q} changes nothing today; it is kept because nothing else guards that
## output if a future release prints one.  Use @code{devtools.selftest} to
## check a configuration before suspecting the host.
##
## @strong{On Windows, name @file{octave-cli.exe} in full.}  A host spawns the
## command with no shell, so a bare @code{octave-cli} resolves only where the
## interpreter is already on @env{PATH}, which a Windows installation does not
## guarantee and a configuration file cannot arrange.  Where it is not, the
## process never starts and writes nothing at all, which reads exactly like the
## corrupted stream above and is nothing to do with it.
##
## @strong{This server sees the packages its own launch command loads, and no
## others.}  The command above loads only @code{devtools}, so
## @code{octave_which} will not find a function from @code{statistics} unless
## it is named:
##
## @example
## --eval "pkg load devtools statistics; devtools.mcp ()"
## @end example
##
## A package's dependencies need not be named: @code{pkg load} loads them too,
## so this also loads @code{datatypes}, which @code{statistics} depends on.
## The server loads nothing on its own.  Loading every installed package
## instead would run each one's @file{PKG_ADD}, which is other people's code
## executing at startup, and this server's whole claim is that it runs none.
##
## @subsubheading Tools
##
## Five tools are served, all of them read-only:
##
## @table @code
## @item octave_which
## where a name resolves, its kind, its owning package, what it shadows, and
## whether it is installed rather than loaded.
##
## @item octave_help
## the help text for a function, class, method or operator, answered from the
## documentation caches where one holds the entry, so that a function in an
## installed package this server has not loaded is answered too.
##
## @item octave_search
## which functions match a description, when the name is not known.
##
## @item octave_pkg
## which packages are installed, at which versions, and which are loaded.
##
## @item octave_registry
## which packages anywhere in the Octave Packages index provide a name, from a
## dated snapshot carried in this package.
## @end table
##
## One resource is offered, @code{octave://environment}: version, platform,
## load path size and the packages this server loaded.  The version and the
## platform are also stated in the server's @code{instructions}, sent once when
## a client connects, so that no request pays for them.
##
## Everything diagnostic goes to standard error, which the protocol reserves for
## exactly that purpose and which a client may capture, forward or ignore.
##
## One deviation is worth stating.  This loop reads, answers and writes in one
## thread, so a @code{notifications/cancelled} arriving for a request already
## being answered cannot be seen until that answer has been written.  The
## protocol asks that no further message be sent for a cancelled request and
## this implementation cannot honour it.  The tools served here return in
## milliseconds, so the window is small, but it is real.
##
## @seealso{devtools.mcpEval, devtools.selftest}
## @end deftypefn

function mcp ()

  if (nargin != 0)
    error ("devtools.mcp: invalid number of input arguments.");
  endif

  devtools.__serveLoop__ ("read-only", "mcp");

endfunction
