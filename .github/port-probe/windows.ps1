# Temporary.  The Windows half of the port probe: whether the filesystem
# confinement can be had without granting a package SID an ACE on the Octave
# installation, and whether a job object caps memory the way prlimit does on
# Linux.  Driven by .github/workflows/port-probe.yml, which parses this file
# before running it so that every syntax error is reported at once.  Delete
# both once the answers are in OCTAVE_DEVTOOLS_PLAN.md.
#
# Nothing here throws on a "no": a refusal is the reading.  Each section is
# independent, so one that fails does not cost the ones behind it.

[CmdletBinding()]
param (
  [string] $OctaveVersion = '11.3.0',
  [string] $SpawnSource = "$PSScriptRoot\spawn.cs"
)

$ErrorActionPreference = 'Continue'
$PSNativeCommandUseErrorActionPreference = $false

$Root = "C:\octave-ci\octave-$OctaveVersion-w64"
$Sys = "$env:SystemRoot\System32"
$AcName = 'devtools-port-probe'
$Launch = "$Root\octave-launch.exe --no-gui --norc --silent --no-history"
$Cli = "$Root\mingw64\bin\octave-cli.exe --norc --no-history"

function Section($title, $body) {
  ''
  "=== $title ==="
  try {
    & $body
  } catch {
    "the section failed: $($_.Exception.Message)"
  }
}

function Show($what, $file) {
  "--- $what ---"
  if (Test-Path $file) { Get-Content $file } else { '(no output)' }
}

# Run one command in the AppContainer under cmd.exe, which supplies the
# redirection CreateProcess cannot, and print what it said.
function InBox($label, $cmd, $out) {
  $e = 0
  $rc = [Spawn]::InAppContainer($AcName, "$Sys\cmd.exe /c $cmd > $out 2>&1",
                                'C:\probe', [ref] $e)
  "$label : exit $rc, error $e"
  Show 'what it printed' $out
}

Add-Type -Path $SpawnSource

Section 'The machine and the installation' {
  [Environment]::OSVersion | Format-List
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $pr = New-Object -TypeName Security.Principal.WindowsPrincipal `
                   -ArgumentList $id
  $admin = [Security.Principal.WindowsBuiltInRole]::Administrator
  'running as admin: ' + $pr.IsInRole($admin)
  "octave root: $Root"
  $f = Get-ChildItem -Recurse -File -ErrorAction SilentlyContinue $Root
  'files: {0}, size: {1:N2} GB' -f $f.Count,
    (($f | Measure-Object -Property Length -Sum).Sum / 1GB)
  '--- the entry points at its root ---'
  Get-ChildItem -File $Root | Select-Object -ExpandProperty Name
  '--- where an octave-cli.exe actually is ---'
  Get-ChildItem -Recurse -Filter octave-cli.exe -ErrorAction SilentlyContinue `
    $Root | Select-Object -ExpandProperty FullName
  '--- what the installation already grants ---'
  icacls $Root
}

Section 'Prepare the probe folders' {
  New-Item -ItemType Directory -Force C:\probe\out | Out-Null
  New-Item -ItemType Directory -Force C:\probe\low | Out-Null
  'secret' | Set-Content C:\probe\secret.txt

  $sid = [Spawn]::AppContainerSid($AcName)
  "AppContainer SID: $sid"
  $sid | Set-Content C:\probe\sid.txt

  # The container needs somewhere to write or nothing it does can be read
  # back.  That grant is on the probe's own folder, never on the Octave
  # installation, which is the thing being measured.  The grant on C:\probe
  # itself does not inherit, so it opens the way to the output folder without
  # opening the secret beside it.
  icacls C:\probe /grant "*${sid}:(RX)" | Out-Null
  icacls C:\probe\out /grant "*${sid}:(OI)(CI)F" | Out-Null
  # A low integrity process writes only where the label allows it.
  icacls C:\probe\low /setintegritylevel '(OI)(CI)L' | Out-Null

  # CreateProcess has no shell, so every launch below goes through cmd.exe
  # for its redirection, and what Octave runs is a file rather than an --eval
  # string, which keeps quotes out of a command line three parsers see.  The
  # files sit in the one folder the container may read.
  'disp (version ()); disp (pwd ())' | Set-Content C:\probe\out\ver.m
  @'
n = str2double (getenv ("PROBE_N"));
t = tic;
try
  x = zeros (n);
  printf ("allocated %.2f GB in %.2f s\n", numel (x) * 8 / 2^30, toc (t));
catch err
  printf ("refused after %.2f s: %s\n", toc (t), err.message);
end_try_catch
'@ | Set-Content C:\probe\out\cap.m
  'folders ready'
}

Section 'AppContainer without an ACE on the installation' {
  $err = 0

  # Nothing below can be read if the container cannot write its output
  # folder, so the first probe touches no file at all and answers with its
  # exit code alone: 42 means the container runs.
  $c = "$Sys\cmd.exe /c exit 42"
  $rc = [Spawn]::InAppContainer($AcName, $c, 'C:\probe', [ref] $err)
  "a container that touches no file: exit $rc (42 expected), error $err"

  # System32 carries ALL APPLICATION PACKAGES by default, so this says
  # whether the container can write where it was granted, before anything is
  # asked of the Octave folder.
  InBox 'cmd.exe from System32' 'ver' C:\probe\out\ver.txt

  # An executable the container owns outright, to show that it may run a
  # program from somewhere other than System32 at all.  If this fails, no
  # grant on the Octave folder could have worked either.
  Copy-Item "$Sys\cmd.exe" C:\probe\out\cmd-copy.exe -Force
  InBox 'a cmd.exe copied into its own folder' `
        'C:\probe\out\cmd-copy.exe /c ver' C:\probe\out\copyexe.txt

  InBox 'listing the Octave folder' "dir `"$Root`"" C:\probe\out\dir.txt
  InBox 'the launcher' "$Launch C:\probe\out\ver.m" C:\probe\out\oct.txt
}

Section 'AppContainer with the ACE, and what the ACE costs' {
  $sid = Get-Content C:\probe\sid.txt
  $err = 0

  # Not Measure-Command: its scriptblock runs in a child scope and what
  # icacls said would not come back out of it.
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $grant = icacls $Root /grant "*${sid}:(OI)(CI)RX" /T /C /Q 2>&1
  $sw.Stop()
  'the grant over the installation took {0:N1} s' -f $sw.Elapsed.TotalSeconds
  '--- what icacls reported ---'
  $grant | Select-Object -Last 3

  # Read and execute are separate rights, and the earlier runs could not say
  # which was refused because the folder was never listed again after the
  # grant.  These four ask in order: does the grant show, can the folder be
  # listed, can a file in it be read, and only then can a program in it run.
  InBox 'the ACL as the container sees it' `
        "icacls `"$Root\octave-launch.exe`"" C:\probe\out\acl.txt
  InBox 'listing the folder again' "dir `"$Root`"" C:\probe\out\dir2.txt
  InBox 'reading a file from it' "type `"$Root\HG-ID`"" C:\probe\out\read.txt
  InBox 'the launcher' "$Launch C:\probe\out\ver.m" C:\probe\out\oct2.txt
  InBox 'the interpreter itself' "$Cli C:\probe\out\ver.m" `
        C:\probe\out\oct2b.txt

  '--- what the container may read, write and reach ---'
  $c = "$Sys\cmd.exe /c " +
       '(type C:\probe\secret.txt & ' +
       'echo x > C:\probe\wrote-here.txt & ' +
       'curl.exe -s -m 10 -o nul -w "http %{http_code}" ' +
       'https://example.com) > C:\probe\out\reach.txt 2>&1'
  $rc = [Spawn]::InAppContainer($AcName, $c, 'C:\probe', [ref] $err)
  "the reach probe: exit $rc, error $err"
  Show 'what it reached' C:\probe\out\reach.txt
  'wrote outside its grant: ' + (Test-Path C:\probe\wrote-here.txt)
}

Section 'A private copy instead of an ACE on the installation' {
  # The escape hatch if a managed image forbids touching the Octave
  # installation: copy it where the profile already has rights.  The cost is
  # disk and one copy, both measured here.
  $sid = Get-Content C:\probe\sid.txt
  $err = 0

  # Take the grant off the installation again, so this arm cannot borrow it.
  icacls $Root /remove "*${sid}" /T /C /Q | Out-Null

  $t = Measure-Command {
    robocopy $Root C:\probe\octave /E /NFL /NDL /NJH /NJS /NP /MT:8 | Out-Null
  }
  $global:LASTEXITCODE = 0
  $f = Get-ChildItem -Recurse -File -ErrorAction SilentlyContinue `
         C:\probe\octave
  'the copy: {0} files, {1:N2} GB, {2:N1} s' -f $f.Count,
    (($f | Measure-Object -Property Length -Sum).Sum / 1GB), $t.TotalSeconds

  $t = Measure-Command {
    icacls C:\probe\octave /grant "*${sid}:(OI)(CI)RX" /T /C /Q | Out-Null
  }
  'granting over the copy took {0:N1} s' -f $t.TotalSeconds

  $copy = 'C:\probe\octave\octave-launch.exe --no-gui --norc --silent ' +
          '--no-history'
  $copyCli = 'C:\probe\octave\mingw64\bin\octave-cli.exe --norc ' +
             '--no-history'
  InBox 'reading a file from the copy' 'type C:\probe\octave\HG-ID' `
        C:\probe\out\read3.txt
  InBox 'the launcher from the copy' "$copy C:\probe\out\ver.m" `
        C:\probe\out\oct3.txt
  InBox 'the interpreter from the copy' "$copyCli C:\probe\out\ver.m" `
        C:\probe\out\oct3b.txt
}

Section 'Whether execution needs ALL APPLICATION PACKAGES' {
  # Every arm above executed only from System32, and System32 is the one place
  # granting ALL APPLICATION PACKAGES rather than a single package SID.  If
  # that is what image execution requires, the lab image question gets harder
  # rather than easier, being the broader grant of the two.
  $aap = 'S-1-15-2-1'
  $err = 0

  # The container's own folder first, where a copied cmd.exe was refused with
  # full control for its own package SID.
  if (! (Test-Path C:\probe\out\cmd-copy.exe)) {
    Copy-Item "$Sys\cmd.exe" C:\probe\out\cmd-copy.exe -Force
  }
  icacls C:\probe\out /grant "*${aap}:(OI)(CI)RX" | Out-Null
  InBox 'the copied cmd.exe, now with ALL APPLICATION PACKAGES' `
        'C:\probe\out\cmd-copy.exe /c ver' C:\probe\out\copyexe2.txt

  $sw = [Diagnostics.Stopwatch]::StartNew()
  $grant = icacls $Root /grant "*${aap}:(OI)(CI)RX" /T /C /Q 2>&1
  $sw.Stop()
  'the grant over the installation took {0:N1} s' -f $sw.Elapsed.TotalSeconds
  $grant | Select-Object -Last 2

  # The folder would not list after (OI)(CI)RX while files inside it read, so
  # the folder itself is granted separately, without inheritance.
  icacls $Root /grant "*${aap}:(RX)" | Out-Null
  InBox 'listing the folder' "dir `"$Root`"" C:\probe\out\dir4.txt
  InBox 'the launcher' "$Launch C:\probe\out\ver.m" C:\probe\out\oct4.txt
  InBox 'the interpreter itself' "$Cli C:\probe\out\ver.m" `
        C:\probe\out\oct4b.txt

  # A confinement that runs Octave is worth nothing if it stopped confining,
  # and the grant just made was read and execute over one tree only.
  '--- what it may still read, write and reach ---'
  $c = "$Sys\cmd.exe /c " +
       '(type C:\probe\secret.txt & ' +
       'echo x > C:\probe\wrote-aap.txt & ' +
       'curl.exe -s -m 10 -o nul -w "http %{http_code}" ' +
       'https://example.com) > C:\probe\out\reach2.txt 2>&1'
  $rc = [Spawn]::InAppContainer($AcName, $c, 'C:\probe', [ref] $err)
  "the reach probe: exit $rc, error $err"
  Show 'what it reached' C:\probe\out\reach2.txt
  'wrote outside its grant: ' + (Test-Path C:\probe\wrote-aap.txt)
}

Section 'A low integrity token, which needs no ACE' {
  $err = 0

  $c = "$Sys\cmd.exe /c $Launch C:\probe\out\ver.m " +
       '> C:\probe\low\oct.txt 2>&1'
  $rc = [Spawn]::AtLowIntegrity($c, 'C:\probe\low', [ref] $err)
  "octave at low integrity: exit $rc, error $err"
  Show 'what it printed' C:\probe\low\oct.txt

  $c = "$Sys\cmd.exe /c " +
       '(type C:\probe\secret.txt & ' +
       'echo x > C:\probe\low-wrote.txt & ' +
       'curl.exe -s -m 10 -o nul -w "http %{http_code}" ' +
       'https://example.com) > C:\probe\low\reach.txt 2>&1'
  $rc = [Spawn]::AtLowIntegrity($c, 'C:\probe\low', [ref] $err)
  "the reach probe at low integrity: exit $rc, error $err"
  Show 'what it reached' C:\probe\low\reach.txt
  'wrote outside the low label: ' + (Test-Path C:\probe\low-wrote.txt)
}

Section 'A job object memory cap' {
  # The Windows half of the memory question.  Unlike RLIMIT_AS this is a
  # documented and enforced per-process cap; what is unknown is whether
  # Octave starts under it and whether an allocation past it comes back as
  # Octave's own error rather than a kill.
  function Cap($mb, $n, $tag) {
    "--- cap $mb MB, zeros ($n) ---"
    $env:PROBE_N = $n
    $c = "$Sys\cmd.exe /c $Launch C:\probe\out\cap.m " +
         "> C:\probe\out\$tag.txt 2>&1"
    $e = 0
    $rc = [Spawn]::InJob($c, 'C:\probe', $mb, [ref] $e)
    "exit $rc, error $e"
    Show 'what it printed' "C:\probe\out\$tag.txt"
  }

  Cap 4096 8000  'job-a'     # 0.48 GB under a 4 GB cap: passes either way
  Cap 4096 24000 'job-b'     # 4.29 GB under a 4 GB cap: refused if it binds
  Cap 512  8000  'job-c'     # does Octave start under half a gigabyte
}

Section 'Is a stronger confinement available at all' {
  # Recorded for the lab image question, not for the runner.
  '--- Windows Sandbox ---'
  Get-WindowsOptionalFeature -Online `
    -FeatureName Containers-DisposableClientVM |
    Select-Object FeatureName, State | Format-List
  '--- Hyper-V ---'
  Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V |
    Select-Object FeatureName, State | Format-List
}

''
'the probe finished'
exit 0
