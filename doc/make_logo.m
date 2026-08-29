## Draw the devtools package logo.
##
## Writes devtools.png (256 by 256) and devtools-wordmark.png (1280 by 400)
## beside itself.  Kept as a script so the logo is reproducible from core
## Octave alone: an outside program, connected to the interpreter, which is
## the whole of what this package is for.

function make_logo ()

  here = fileparts (mfilename ('fullpath'));

  ## The mark, which is what package_texi2html and the Qt help consume.  It
  ## is drawn at 25 pixels in the generated pages, so it carries no text.
  f = figure ('visible', 'off', 'color', 'w');
  ax = axes ('parent', f, 'position', [0, 0, 1, 1]);
  hold (ax, 'on');
  mark (ax, 2, 26, 1);
  axis (ax, 'equal');
  axis (ax, 'off');
  set (ax, 'xlim', [0, 100], 'ylim', [0, 100]);
  set (f, 'paperunits', 'inches', 'papersize', [2.56, 2.56], ...
       'paperposition', [0, 0, 2.56, 2.56]);
  print (f, fullfile (here, 'devtools.png'), '-dpng', '-r100');
  close (f);

  ## The wordmark, for the head of a README or a repository preview, where
  ## the name is large enough to read.
  f = figure ('visible', 'off', 'color', 'w');
  ax = axes ('parent', f, 'position', [0, 0, 1, 1]);
  hold (ax, 'on');
  mark (ax, 14, 30, 1);
  text (210, 58, 'devtools', 'parent', ax, 'fontsize', 46, ...
        'color', [0.11, 0.11, 0.11], 'horizontalalignment', 'center', ...
        'verticalalignment', 'middle', 'interpreter', 'none');
  line ('parent', ax, 'xdata', [14, 306], 'ydata', [20, 20], ...
        'color', [0.94, 0.50, 0.12], 'linewidth', 5);
  axis (ax, 'off');
  set (ax, 'xlim', [0, 320], 'ylim', [0, 100]);
  set (f, 'paperunits', 'inches', 'papersize', [8, 2.5], ...
       'paperposition', [0, 0, 8, 2.5]);
  print (f, fullfile (here, 'devtools-wordmark.png'), '-dpng', '-r160');
  close (f);

endfunction

function mark (ax, x, y, s)
  ## An orange plug, connected to the interpreter, which holds the prompt
  ## inside the braces of a protocol message.  (X, Y) is the lower left of
  ## the plug and S scales the whole.
  blue   = [0.04, 0.56, 0.75];
  orange = [0.94, 0.50, 0.12];

  fill_ (ax, roundrect (x+32*s, y, 62*s, 48*s, 10*s), blue);
  fill_ (ax, roundrect (x, y+10*s, 16*s, 28*s, 5*s), orange);
  line ('parent', ax, 'xdata', [x+16*s, x+34*s], 'ydata', (y+31*s)*[1, 1], ...
        'color', orange, 'linewidth', 7*s);
  line ('parent', ax, 'xdata', [x+16*s, x+34*s], 'ydata', (y+17*s)*[1, 1], ...
        'color', orange, 'linewidth', 7*s);

  glyph (ax, x+46*s, y+25*s, '{',  44*s, 'normal');
  glyph (ax, x+63*s, y+24*s, '>>', 26*s, 'bold');
  glyph (ax, x+80*s, y+25*s, '}',  44*s, 'normal');
endfunction

function glyph (ax, x, y, str, fs, wt)
  text (x, y, str, 'parent', ax, 'fontsize', fs, 'fontweight', wt, ...
        'color', 'w', 'horizontalalignment', 'center', ...
        'verticalalignment', 'middle', 'interpreter', 'none');
endfunction

function fill_ (ax, V, fc)
  patch ('parent', ax, 'xdata', V(:,1), 'ydata', V(:,2), ...
         'facecolor', fc, 'edgecolor', 'none');
endfunction

function V = roundrect (x, y, w, h, r, n)
  if (nargin < 6)
    n = 14;
  endif
  a = linspace (0, pi/2, n)';
  V = [ [x+w-r, y+r]   + r * [cos(a-pi/2), sin(a-pi/2)];
        [x+w-r, y+h-r] + r * [cos(a),      sin(a)];
        [x+r,   y+h-r] + r * [cos(a+pi/2), sin(a+pi/2)];
        [x+r,   y+r]   + r * [cos(a+pi),   sin(a+pi)] ];
endfunction
