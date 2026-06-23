/*
   IR starter YARA rules — generic triage heuristics, NOT a substitute for a
   curated set (see ../README.md). These are intentionally broad/noisy and meant
   to surface *candidates* during triage, expecting analyst review. Replace with
   YARA-Forge / signature-base for real coverage.
*/

rule IR_Suspicious_PowerShell_Encoded
{
    meta:
        description = "Encoded / download-cradle PowerShell often used by droppers"
        author      = "WindowsIR-Toolkit"
        severity    = "medium"
    strings:
        $a1 = "-enc"           nocase ascii wide
        $a2 = "-EncodedCommand" nocase ascii wide
        $a3 = "FromBase64String" nocase ascii wide
        $a4 = "IEX"            nocase ascii wide
        $a5 = "Invoke-Expression" nocase ascii wide
        $a6 = "DownloadString" nocase ascii wide
        $a7 = "Net.WebClient"  nocase ascii wide
        $a8 = "-w hidden"      nocase ascii wide
        $a9 = "-nop"           nocase ascii wide
    condition:
        3 of them
}

rule IR_Suspicious_LOLBin_Cradle
{
    meta:
        description = "Living-off-the-land download/exec patterns (mshta/regsvr32/certutil/bitsadmin)"
        severity    = "medium"
    strings:
        $s1 = "mshta"   nocase ascii wide
        $s2 = "regsvr32" nocase ascii wide
        $s3 = "certutil -urlcache" nocase ascii wide
        $s4 = "certutil -decode"   nocase ascii wide
        $s5 = "bitsadmin /transfer" nocase ascii wide
        $s6 = "rundll32" nocase ascii wide
        $url = /https?:\/\/[a-z0-9\.\-]+\/[^\s"']+\.(exe|dll|ps1|hta|scr|bat)/ nocase ascii wide
    condition:
        $url and 1 of ($s*)
}

rule IR_Webshell_Common
{
    meta:
        description = "Common webshell eval/exec sinks (PHP/ASPX/JSP)"
        severity    = "high"
    strings:
        $p1 = "eval($_POST"   nocase ascii wide
        $p2 = "eval($_GET"    nocase ascii wide
        $p3 = "eval(base64_decode" nocase ascii wide
        $p4 = "system($_REQUEST" nocase ascii wide
        $a1 = "Request.Item"  nocase ascii wide
        $a2 = "Server.CreateObject(\"WScript.Shell\")" nocase ascii wide
        $j1 = "Runtime.getRuntime().exec" nocase ascii wide
    condition:
        any of them
}

rule IR_Mimikatz_Strings
{
    meta:
        description = "Mimikatz credential-dumping strings (often in memory dumps)"
        severity    = "critical"
    strings:
        $m1 = "sekurlsa::logonpasswords" nocase ascii wide
        $m2 = "gentilkiwi" nocase ascii wide
        $m3 = "mimikatz"   nocase ascii wide
        $m4 = "privilege::debug" nocase ascii wide
        $m5 = "lsadump::"  nocase ascii wide
    condition:
        any of them
}

rule IR_Suspicious_Dropper_Paths
{
    meta:
        description = "Executable content referencing user-writable drop locations"
        severity    = "low"
    strings:
        $t1 = "\\AppData\\Local\\Temp\\" nocase ascii wide
        $t2 = "\\Users\\Public\\"        nocase ascii wide
        $t3 = "\\ProgramData\\"          nocase ascii wide
        $mz = { 4D 5A }   // PE header
    condition:
        $mz at 0 and 1 of ($t*)
}
