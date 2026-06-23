/*
   macOS IR Toolkit -- starter YARA heuristics.
   Intentionally small and HIGH-LEVEL. Replace/augment with curated feeds for real
   hunts (see iocs/README.md): YARAify, Neo23x0/signature-base, Objective-See.
   These are triage heuristics, not high-fidelity detections -- expect FPs.
*/

import "macho"

rule macOS_Macho_Suspicious_Strings
{
    meta:
        description = "Mach-O binary referencing common offensive/persistence primitives"
        author      = "macOS IR Toolkit"
        severity    = "informational"
    strings:
        $s1 = "osascript" ascii
        $s2 = "/usr/bin/curl" ascii
        $s3 = "launchctl load" ascii
        $s4 = "LaunchAgents" ascii
        $s5 = "kTCCServiceAccessibility" ascii
        $s6 = "AppleScript" ascii
        $s7 = "/bin/bash -c" ascii
    condition:
        macho.magic == 0xfeedfacf and 3 of ($s*)
}

rule macOS_Persistence_Plist_RunAtLoad
{
    meta:
        description = "launchd plist that runs a payload at load from a writable/temp path"
        author      = "macOS IR Toolkit"
        severity    = "low"
    strings:
        $run = "RunAtLoad" ascii nocase
        $p1  = "/tmp/" ascii
        $p2  = "/Users/Shared/" ascii
        $p3  = "/private/tmp/" ascii
        $p4  = "/var/tmp/" ascii
        $sh  = "ProgramArguments" ascii
    condition:
        $run and $sh and any of ($p1,$p2,$p3,$p4)
}

rule macOS_Script_Reverse_Shell_Hints
{
    meta:
        description = "Shell/script reverse-shell or download-cradle indicators"
        author      = "macOS IR Toolkit"
        severity    = "low"
    strings:
        $r1 = "bash -i >& /dev/tcp/" ascii
        $r2 = "nc -e /bin/sh" ascii
        $r3 = "python -c 'import socket" ascii
        $r4 = "curl -s http" ascii
        $r5 = "| /bin/sh" ascii
        $r6 = "eval(base64" ascii nocase
    condition:
        any of them
}
