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
## @deftypefn  {} {} regen_index (@var{srcdir})
## @deftypefnx {} {@var{M} =} regen_index (@var{srcdir})
##
## Refresh the vendored ecosystem index from a @code{pkg-functions} checkout.
##
## @code{regen_index (@var{srcdir})} copies @file{data/functions.json} and
## @file{data/index.json} from the @code{pkg-functions} working copy at
## @var{srcdir} into @file{inst/data/} here, and writes
## @file{inst/data/MANIFEST.json} recording where they came from and when.
##
## This is a release step, run by hand.  @code{pkg-functions} harvests hourly;
## the copy carried here is frozen at whatever release last ran this, and is
## reported as such by @code{octave_registry}.  Nothing fetches anything: the
## server never contacts the network, and a snapshot that could silently
## change under a user would be a different promise from the one this package
## makes.
##
## @file{history.json} is deliberately not copied.  It is the only file that
## answers "since which version did this package provide this name", and it is
## larger than everything else here put together; @file{index.json} already
## carries each package's newest version and release date, which is what dates
## an answer.
##
## @code{@var{M} = regen_index (@var{srcdir})} returns the manifest as a
## structure rather than printing a report.
##
## @seealso{mcp.serve}
## @end deftypefn

function M = regen_index (srcdir)

  if (nargin != 1 || ! (ischar (srcdir) && isrow (srcdir)))
    error ("regen_index: SRCDIR must be a character vector.");
  endif
  if (exist (srcdir, "dir") != 7)
    error ("regen_index: '%s' is not a directory.", srcdir);
  endif

  want = {'functions.json', 'index.json'};
  for i = 1:numel (want)
    if (exist (fullfile (srcdir, "data", want{i}), "file") != 2)
      error (strcat ("regen_index: '%s' has no data/%s; SRCDIR must be a", ...
                     " pkg-functions working copy."), srcdir, want{i});
    endif
  endfor

  here = fileparts (mfilename ("fullpath"));
  dest = fullfile (here, "inst", "data");
  if (exist (dest, "dir") != 7)
    mkdir (dest);
  endif

  ## Octave's jsondecode turns object keys into struct fields, and 44% of the
  ## names here carry a dot (every Class.method entry), so the true name cannot
  ## be read back from a decoded key.  The keys are therefore lifted from the
  ## text with a regexp and paired with the decoded values by position, which
  ## is checked below rather than assumed.
  [names, kinds, pkgs] = readFunctions (fullfile (srcdir, "data", "functions.json"));
  [pn, pl, pd] = readIndex (fullfile (srcdir, "data", "index.json"));

  ## Sorted once here so that a lookup is a binary search rather than a scan
  [names, ix] = sort (names);
  kinds = kinds(ix);
  pkgs = pkgs(ix);

  E = struct ();
  E.names = names;
  E.kinds = kinds;
  E.packages = pkgs;
  E.pkgNames = pn;
  E.pkgLatest = pl;
  E.pkgDate = pd;

  outfile = fullfile (dest, "ecosystem.json");
  fid = fopen (outfile, "w");
  if (fid < 0)
    error ("regen_index: cannot write %s.", outfile);
  endif
  unwind_protect
    fputs (fid, jsonencode (E));
  unwind_protect_cleanup
    fclose (fid);
  end_unwind_protect

  M = struct ();
  M.source = "pkg-functions";
  M.sourceUrl = "https://github.com/pr0m1th3as/pkg-functions";
  M.commit = gitField (srcdir, "%H");
  M.commitDate = gitField (srcdir, "%cI");
  M.captured = datestr (now (), "yyyy-mm-dd");
  M.note = strcat ("A snapshot, not a live view. pkg-functions harvests", ...
                   " hourly; this copy is frozen at the date above.");
  d = dir (outfile);
  M.rows = numel (names);
  M.packages = numel (pn);
  M.bytes = d.bytes;

  fid = fopen (fullfile (dest, "MANIFEST.json"), "w");
  if (fid < 0)
    error ("regen_index: cannot write the manifest in %s.", dest);
  endif
  unwind_protect
    fputs (fid, jsonencode (M));
  unwind_protect_cleanup
    fclose (fid);
  end_unwind_protect

  if (nargout == 0)
    printf ("ecosystem index refreshed into %s\n", dest);
    printf ("  source    %s at %s\n", M.source, M.commit(1:min (12, numel (M.commit))));
    printf ("  committed %s\n", M.commitDate);
    printf ("  captured  %s\n", M.captured);
    printf ("  ecosystem.json %7.0f KB  %d rows over %d packages\n", ...
            M.bytes / 1024, M.rows, M.packages);
    clear M;
  endif

endfunction

function [names, kinds, pkgs] = readFunctions (f)

  ## Read the names from the text, not through jsondecode.  Octave mangles an
  ## object key that is not a valid identifier, and 44% of these names carry a
  ## dot, so a decoded key is not the name.  Worse, the mangling is not a
  ## character substitution: the key "end" is a reserved word and comes back as
  ## "xEnd", so no rule recovers the original.  These files are machine
  ## generated and regular, which is what makes reading them directly safe here
  ## and would not make it safe in general.  The counts are checked below.

  txt = fileread (f);
  hits = regexp (txt, '"([^"]+)":(\[[^\]]*\])', "tokens");

  names = {};
  kinds = {};
  pkgs = {};
  for i = 1:numel (hits)
    nm = hits{i}{1};
    recs = regexp (hits{i}{2}, '"kind":"([^"]*)","package":"([^"]*)"', "tokens");
    for k = 1:numel (recs)
      names{end+1} = nm;
      kinds{end+1} = recs{k}{1};
      pkgs{end+1} = recs{k}{2};
    endfor
  endfor

  ## Every kind field in the file must have produced exactly one row
  want = numel (strfind (txt, '"kind":'));
  if (numel (names) != want)
    error (strcat ("regen_index: %s has %d kind fields but yielded %d rows;", ...
                   " the file is not the shape this expects."), f, want, ...
           numel (names));
  endif

endfunction

function [pn, latest, dt] = readIndex (f)

  txt = fileread (f);
  hits = regexp (txt, '"([^"]+)":(\{[^}]*\})', "tokens");

  pn = cell (1, numel (hits));
  latest = cell (1, numel (hits));
  dt = cell (1, numel (hits));
  for i = 1:numel (hits)
    pn{i} = hits{i}{1};
    latest{i} = jsonField (hits{i}{2}, "latest");
    dt{i} = jsonField (hits{i}{2}, "date");
  endfor

  if (isempty (pn))
    error ("regen_index: %s yielded no packages.", f);
  endif

endfunction

function v = jsonField (obj, key)
  t = regexp (obj, ['"' key '":"([^"]*)"'], "tokens", "once");
  if (isempty (t))
    v = "";
  else
    v = t{1};
  endif
endfunction

function v = gitField (dir, fmt)
  ## The commit is what makes the copy reproducible; without it the snapshot
  ## is a pile of numbers of unknown ancestry
  [status, out] = system (sprintf ('git -C "%s" log -1 --format=%s 2>/dev/null', ...
                                   dir, fmt));
  if (status != 0 || isempty (strtrim (out)))
    v = "unknown";
  else
    v = strtrim (out);
  endif
endfunction
