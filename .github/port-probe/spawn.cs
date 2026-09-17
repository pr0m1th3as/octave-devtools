/* Temporary.  The process spawner for the Windows half of the port
   probe: an AppContainer, a low integrity token and a job object
   memory cap.  Loaded by windows.ps1, which the workflow compiles
   before it runs anything.  Delete both once the answers are in
   OCTAVE_DEVTOOLS_PLAN.md.  */

using System;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;

public static class Spawn
{
  [StructLayout (LayoutKind.Sequential)]
  public struct STARTUPINFO {
    public int cb; public IntPtr r1, d, t;
    public int dwX, dwY, dwXSize, dwYSize, dwXCountChars,
               dwYCountChars, dwFillAttribute, dwFlags;
    public short wShowWindow, cbReserved2;
    public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
  }
  [StructLayout (LayoutKind.Sequential)]
  public struct STARTUPINFOEX {
    public STARTUPINFO StartupInfo; public IntPtr lpAttributeList;
  }
  [StructLayout (LayoutKind.Sequential)]
  public struct PROCESS_INFORMATION {
    public IntPtr hProcess, hThread; public int pid, tid;
  }
  [StructLayout (LayoutKind.Sequential)]
  public struct SECURITY_CAPABILITIES {
    public IntPtr AppContainerSid, Capabilities;
    public int CapabilityCount, Reserved;
  }
  [StructLayout (LayoutKind.Sequential)]
  public struct SID_AND_ATTRIBUTES {
    public IntPtr Sid; public uint Attributes;
  }
  [StructLayout (LayoutKind.Sequential)]
  public struct TOKEN_MANDATORY_LABEL {
    public SID_AND_ATTRIBUTES Label;
  }
  [StructLayout (LayoutKind.Sequential)]
  public struct IO_COUNTERS {
    public ulong a, b, c, d, e, f;
  }
  [StructLayout (LayoutKind.Sequential)]
  public struct JOBOBJECT_BASIC_LIMIT_INFORMATION {
    public long PerProcessUserTimeLimit, PerJobUserTimeLimit;
    public uint LimitFlags;
    public UIntPtr MinimumWorkingSetSize, MaximumWorkingSetSize;
    public uint ActiveProcessLimit;
    public UIntPtr Affinity;
    public uint PriorityClass, SchedulingClass;
  }
  [StructLayout (LayoutKind.Sequential)]
  public struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION {
    public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
    public IO_COUNTERS IoInfo;
    public UIntPtr ProcessMemoryLimit, JobMemoryLimit,
                   PeakProcessMemoryUsed, PeakJobMemoryUsed;
  }

  [DllImport ("userenv.dll", CharSet = CharSet.Unicode)]
  static extern int CreateAppContainerProfile (string name,
    string display, string desc, IntPtr caps, int count,
    out IntPtr sid);
  [DllImport ("userenv.dll", CharSet = CharSet.Unicode)]
  static extern int DeriveAppContainerSidFromAppContainerName (
    string name, out IntPtr sid);
  [DllImport ("kernel32.dll", SetLastError = true)]
  static extern bool InitializeProcThreadAttributeList (IntPtr list,
    int count, int flags, ref IntPtr size);
  [DllImport ("kernel32.dll", SetLastError = true)]
  static extern bool UpdateProcThreadAttribute (IntPtr list,
    uint flags, IntPtr attribute, IntPtr value, IntPtr size,
    IntPtr previous, IntPtr returned);
  [DllImport ("kernel32.dll", SetLastError = true,
              CharSet = CharSet.Unicode)]
  static extern bool CreateProcess (string app, StringBuilder cmd,
    IntPtr pa, IntPtr ta, bool inherit, uint flags, IntPtr env,
    string cwd, ref STARTUPINFOEX si, out PROCESS_INFORMATION pi);
  [DllImport ("advapi32.dll", SetLastError = true,
              CharSet = CharSet.Unicode)]
  static extern bool CreateProcessAsUser (IntPtr token, string app,
    StringBuilder cmd, IntPtr pa, IntPtr ta, bool inherit,
    uint flags, IntPtr env, string cwd, ref STARTUPINFO si,
    out PROCESS_INFORMATION pi);
  [DllImport ("advapi32.dll", SetLastError = true,
              CharSet = CharSet.Unicode)]
  static extern bool CreateProcessWithTokenW (IntPtr token,
    uint logonFlags, string app, StringBuilder cmd, uint flags,
    IntPtr env, string cwd, ref STARTUPINFO si,
    out PROCESS_INFORMATION pi);
  [DllImport ("advapi32.dll", SetLastError = true)]
  static extern bool OpenProcessToken (IntPtr proc, uint access,
    out IntPtr token);
  [DllImport ("advapi32.dll", SetLastError = true)]
  static extern bool DuplicateTokenEx (IntPtr token, uint access,
    IntPtr sa, int level, int type, out IntPtr dup);
  [DllImport ("advapi32.dll", SetLastError = true)]
  static extern bool SetTokenInformation (IntPtr token, int cls,
    ref TOKEN_MANDATORY_LABEL info, int length);
  [DllImport ("advapi32.dll", SetLastError = true,
              CharSet = CharSet.Unicode)]
  static extern bool ConvertStringSidToSid (string s, out IntPtr sid);
  [DllImport ("kernel32.dll", SetLastError = true,
              CharSet = CharSet.Unicode)]
  static extern IntPtr CreateJobObject (IntPtr sa, string name);
  [DllImport ("kernel32.dll", SetLastError = true)]
  static extern bool SetInformationJobObject (IntPtr job, int cls,
    IntPtr info, int length);
  [DllImport ("kernel32.dll", SetLastError = true)]
  static extern bool AssignProcessToJobObject (IntPtr job,
    IntPtr proc);
  [DllImport ("kernel32.dll", SetLastError = true)]
  static extern uint ResumeThread (IntPtr thread);
  [DllImport ("kernel32.dll", SetLastError = true)]
  static extern uint WaitForSingleObject (IntPtr h, uint ms);
  [DllImport ("kernel32.dll", SetLastError = true)]
  static extern bool GetExitCodeProcess (IntPtr h, out uint code);
  [DllImport ("kernel32.dll")]
  static extern IntPtr GetCurrentProcess ();
  [DllImport ("kernel32.dll")]
  static extern bool CloseHandle (IntPtr h);

  const uint EXTENDED_STARTUPINFO_PRESENT = 0x00080000;
  const uint CREATE_SUSPENDED = 0x00000004;
  const uint CREATE_NO_WINDOW = 0x08000000;
  static readonly IntPtr SECURITY_CAPABILITIES_ATTRIBUTE =
    (IntPtr) 0x00020009;

  /* The profile's SID, made on the first call, derived after. */
  public static string AppContainerSid (string name)
  {
    IntPtr sid;
    int hr = CreateAppContainerProfile (name, name,
                                        "devtools port probe",
                                        IntPtr.Zero, 0, out sid);
    if (hr != 0)
      {
        hr = DeriveAppContainerSidFromAppContainerName (name,
                                                       out sid);
        if (hr != 0)
          throw new Exception ("no AppContainer SID: 0x"
                               + hr.ToString ("X8"));
      }
    return new SecurityIdentifier (sid).Value;
  }

  /* Run CMD in the AppContainer of that name.  Returns the exit
     code, or -1 when the process could not be created at all, the
     Win32 error following in ERR. */
  public static int InAppContainer (string name, string cmd,
                                    string cwd, out int err)
  {
    err = 0;
    IntPtr sid;
    if (DeriveAppContainerSidFromAppContainerName (name, out sid)
        != 0)
      throw new Exception ("the profile does not exist");

    var caps = new SECURITY_CAPABILITIES ();
    caps.AppContainerSid = sid;
    caps.Capabilities = IntPtr.Zero;
    caps.CapabilityCount = 0;

    IntPtr size = IntPtr.Zero;
    InitializeProcThreadAttributeList (IntPtr.Zero, 1, 0, ref size);
    IntPtr list = Marshal.AllocHGlobal (size);
    if (! InitializeProcThreadAttributeList (list, 1, 0, ref size))
      { err = Marshal.GetLastWin32Error (); return -1; }

    int n = Marshal.SizeOf (typeof (SECURITY_CAPABILITIES));
    IntPtr pcaps = Marshal.AllocHGlobal (n);
    Marshal.StructureToPtr (caps, pcaps, false);
    if (! UpdateProcThreadAttribute (list, 0,
            SECURITY_CAPABILITIES_ATTRIBUTE, pcaps, (IntPtr) n,
            IntPtr.Zero, IntPtr.Zero))
      { err = Marshal.GetLastWin32Error (); return -1; }

    var si = new STARTUPINFOEX ();
    si.StartupInfo.cb = Marshal.SizeOf (typeof (STARTUPINFOEX));
    si.lpAttributeList = list;
    PROCESS_INFORMATION pi;
    if (! CreateProcess (null, new StringBuilder (cmd),
                         IntPtr.Zero, IntPtr.Zero, false,
                         EXTENDED_STARTUPINFO_PRESENT
                         | CREATE_NO_WINDOW,
                         IntPtr.Zero, cwd, ref si, out pi))
      { err = Marshal.GetLastWin32Error (); return -1; }

    WaitForSingleObject (pi.hProcess, 300000);
    uint code;
    GetExitCodeProcess (pi.hProcess, out code);
    CloseHandle (pi.hThread);
    CloseHandle (pi.hProcess);
    return (int) code;
  }

  /* Run CMD with this process's token lowered to low integrity. */
  public static int AtLowIntegrity (string cmd, string cwd,
                                    out int err)
  {
    err = 0;
    IntPtr token, dup, low;
    OpenProcessToken (GetCurrentProcess (), 0xF01FF, out token);
    if (! DuplicateTokenEx (token, 0xF01FF, IntPtr.Zero, 2, 1,
                            out dup))
      { err = Marshal.GetLastWin32Error (); return -1; }
    ConvertStringSidToSid ("S-1-16-4096", out low);
    var label = new TOKEN_MANDATORY_LABEL ();
    label.Label.Sid = low;
    label.Label.Attributes = 0x20;      /* SE_GROUP_INTEGRITY */
    int n = Marshal.SizeOf (typeof (TOKEN_MANDATORY_LABEL)) + 16;
    if (! SetTokenInformation (dup, 25, ref label, n))
      { err = Marshal.GetLastWin32Error (); return -1; }

    var si = new STARTUPINFO ();
    si.cb = Marshal.SizeOf (typeof (STARTUPINFO));
    PROCESS_INFORMATION pi;
    /* CreateProcessAsUser wants a privilege that a session may not
       have enabled; CreateProcessWithTokenW wants only the one an
       administrator holds, so it is the fallback rather than the
       first choice, its logon flags being the coarser interface. */
    if (! CreateProcessAsUser (dup, null, new StringBuilder (cmd),
                               IntPtr.Zero, IntPtr.Zero, false,
                               CREATE_NO_WINDOW, IntPtr.Zero, cwd,
                               ref si, out pi))
      {
        err = Marshal.GetLastWin32Error ();
        if (! CreateProcessWithTokenW (dup, 0, null,
                                       new StringBuilder (cmd),
                                       CREATE_NO_WINDOW,
                                       IntPtr.Zero, cwd, ref si,
                                       out pi))
          { err = Marshal.GetLastWin32Error (); return -1; }
        err = 0;
      }

    WaitForSingleObject (pi.hProcess, 300000);
    uint code;
    GetExitCodeProcess (pi.hProcess, out code);
    CloseHandle (pi.hThread);
    CloseHandle (pi.hProcess);
    return (int) code;
  }

  /* Run CMD in a job object capping one process at MB megabytes. */
  public static int InJob (string cmd, string cwd, long mb,
                           out int err)
  {
    err = 0;
    IntPtr job = CreateJobObject (IntPtr.Zero, null);
    if (job == IntPtr.Zero)
      { err = Marshal.GetLastWin32Error (); return -1; }

    var info = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION ();
    info.BasicLimitInformation.LimitFlags = 0x00000100;
    info.ProcessMemoryLimit = (UIntPtr) (ulong) (mb * 1024 * 1024);
    int len = Marshal.SizeOf (
      typeof (JOBOBJECT_EXTENDED_LIMIT_INFORMATION));
    IntPtr p = Marshal.AllocHGlobal (len);
    Marshal.StructureToPtr (info, p, false);
    if (! SetInformationJobObject (job, 9, p, len))
      { err = Marshal.GetLastWin32Error (); return -1; }

    var si = new STARTUPINFOEX ();
    si.StartupInfo.cb = Marshal.SizeOf (typeof (STARTUPINFO));
    PROCESS_INFORMATION pi;
    if (! CreateProcess (null, new StringBuilder (cmd),
                         IntPtr.Zero, IntPtr.Zero, false,
                         CREATE_SUSPENDED | CREATE_NO_WINDOW,
                         IntPtr.Zero, cwd, ref si, out pi))
      { err = Marshal.GetLastWin32Error (); return -1; }
    if (! AssignProcessToJobObject (job, pi.hProcess))
      { err = Marshal.GetLastWin32Error (); return -1; }
    ResumeThread (pi.hThread);

    WaitForSingleObject (pi.hProcess, 300000);
    uint code;
    GetExitCodeProcess (pi.hProcess, out code);
    CloseHandle (pi.hThread);
    CloseHandle (pi.hProcess);
    return (int) code;
  }
}
