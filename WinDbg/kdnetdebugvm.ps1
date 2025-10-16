#
# Argument initialization
#

$nextarg = "none"
$DebugPort = "unassigned"
$targetcomputer = "."
$VMName = ""
$VMGuid = ""
$AutoAssign = "false"
$DebugOff = "false"

function funHelp()
{
$helpText=@"

DESCRIPTION:
NAME: kdnetdebugvm.ps1
Displays (and optionally sets) the port used to network debug a VM.

PARAMETERS: 
-computerName Specifies the name of the computer on which to run the script
-help         Displays help
-vmname       (optional) Name of the VM of interest
-vmguid       (optional) GUID of the VM of interest
-port         (optional) Network port to use for debugging
-debugoff
-autoassign

Either vmname or vmguid must be specified to identify the VM, but not both.
Note that vmname may not uniquely identify the VM, but vmguid does.

SYNTAX:
kdnetdebugvm.ps1 [-computerName targetcomputer] [-vmname NameOfVM] [-vmguid GuidOfVM] [-port PortNumber]

"@
$helpText
exit
}


foreach ($argument in $args)
{
    # parse commands with no following arguments
    switch ($argument)
    {
        "?"     {funHelp}
        "help"  {funHelp}
        "-help" {funHelp}
        "/?"    {funHelp}
        "-?"    {funHelp}
        "autoassign"    {$AutoAssign = "true"}
        "-autoassign"   {$AutoAssign = "true"}
        "/autoassign"   {$AutoAssign = "true"}
        "debugoff"        {$DebugOff = "true"}
        "-debugoff"       {$DebugOff = "true"}
        "/debugoff"       {$DebugOff = "true"}
        default {}
    }

    # parse values that followed a switch

    switch ($nextarg)
    {
        "vmname"        {$VMName = $argument}
        "-vmname"       {$VMName = $argument}
        "/vmname"       {$VMName = $argument}
        "vmguid"        {$VMGuid = $argument}
        "-vmguid"       {$VMGuid = $argument}
        "/vmguid"       {$VMGuid = $argument}
        "port"          {$DebugPort = $argument}
        "-port"         {$DebugPort = $argument}
        "/port"         {$DebugPort = $argument}
        "computername"  {$targetcomputer = $argument}
        "-computername" {$targetcomputer = $argument}
        "/computername" {$targetcomputer = $argument}
        default         {}
    }

    $nextarg = $argument
}

if (($VMName -eq "") -and ($VMGuid -eq ""))
{
    funHelp
}

if (($VMName -ne "") -and ($VMGuid -ne ""))
{
    funHelp
}

$ns = "root\virtualization\v2"
$VMWPName = "$env:windir\system32\vmwp.exe"

#Get a VMManagementService object
$VMManagementService = gwmi -class "Msvm_VirtualSystemManagementService" -namespace $ns -computername $targetcomputer

#Get the VM object that we want to modify
if ($VMName -ne "")
{
    $VM = Get-VM -computername $targetcomputer -VMName $VMName
}

if ($VMGuid -ne "")
{
    $VM = Get-VM -computername $targetcomputer -Id $VMGuid
}

#Get the VirtualSystemGlobalSettingData of the VM we want to modify
$VMSystemGlobalSettingData = gwmi -namespace $ns -computername $targetcomputer -class Msvm_VirtualSystemSettingData | ? { $_.ConfigurationID -eq $VM.Id }

# Set a new debugport
if ($DebugPort -ne "unassigned")
{
    #Change the ElementName property
    $VMSystemGlobalSettingData.DebugPort = $DebugPort
    $VMSystemGlobalSettingData.DebugPortEnabled = 1

    $VMManagementService.ModifySystemSettings($VMSystemGlobalSettingData.GetText(1))
    $FWRuleName = "SynthDebugInboundRule-$DebugPort"
    New-NetFirewallRule -DisplayName $FWRuleName -Program $VMWPName -Protocol UDP -Action Allow -Direction Inbound -LocalPort $DebugPort
}

# Enable auto assigned debug ports
if ($AutoAssign -ne "false")
{
    #Change the ElementName property
    $VMSystemGlobalSettingData.DebugPortEnabled = 2
    $VMManagementService.ModifySystemSettings($VMSystemGlobalSettingData.GetText(1))
    Write-Host -Foreground Yellow "Firewall Ports for autoassign mode can be opened only after the VM is started."
}

# Turn off debugging
if ($DebugOff -ne "false")
{
    $DebugPort = $VMSystemGlobalSettingData.DebugPort
    #Change the ElementName property
    $VMSystemGlobalSettingData.DebugPortEnabled = 0
    $VMSystemGlobalSettingData.DebugPort = 0
    $VMManagementService.ModifySystemSettings($VMSystemGlobalSettingData.GetText(1))
    # May throw an exception if the rule did not exist already.
    # If two rules exist with the same name, both will be deleted.
    if ($DebugPort -ne 0)
    {
        $FWRuleName = "SynthDebugInboundRule-$DebugPort"
        Remove-NetFirewallRule -DisplayName $FWRuleName
    }
}

$VMSystemGlobalSettingData

exit

# SIG # Begin signature block
# MIIpjwYJKoZIhvcNAQcCoIIpgDCCKXwCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDbHDLYuqp9Du8W
# ZSYoLwjEyhkYywkzwemxEtpUqBqajKCCDeUwgga9MIIEpaADAgECAhMzAAAAHEif
# gd+hsLd3AAAAAAAcMA0GCSqGSIb3DQEBDAUAMIGIMQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0
# aWZpY2F0ZSBBdXRob3JpdHkgMjAxMDAeFw0yNDA4MDgyMTM2MjNaFw0zNTA2MjMy
# MjA0MDFaMF8xCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9y
# YXRpb24xMDAuBgNVBAMTJ01pY3Jvc29mdCBXaW5kb3dzIENvZGUgU2lnbmluZyBQ
# Q0EgMjAyNDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAJp9a30nwXYq
# Lq7j1TT/zCtt7vxU+CCj+7BkifS/B2gXKGU7OV9SXRJGP1yFs5p6jpsYi4cYzF56
# AV0AEmmEjV8wT2lvPU5BhN3wV30HqYPIYEj5P3WXf0kXD9fvjUf1GAtXEriJ8w7A
# LNaVEm9Rs4ePA0ZsYHaCbU5kBUJQDXv76hafOcQgdFCA3I3zYtfzX2vOwx87uDOa
# CuyKORZih9c3zTf+TLC5QYLyhVMBnDXEHDOrvaw92DSyIqpdgRWpufzqDFy1egVj
# koXZhb+9pZ9heUzNXTXhOoXzexh6YzAL4flBWm+Bc1hQyESenEvBJznV+25u3h77
# jjgMUY44+WXQ4u9qddDe/U5SeAaKRvvibmi4z7QRpLvZsla0CPiOUGz00Do5sfkC
# 0EwlsSzfM3+8A9rsyFVOgWDVPzt98OJP2EoaEOq8GE9GCoN2i7/4C2FCwff1BSCT
# JWZO1Wcr2MteJE6UxGV+ihA8nN51YPKD2dYGoewrXvRzC/1HoUeSvlZf0mf9GHEt
# vvkbJVRRo6PBf0md5t87Vb1mM/fIp1eypyaxmXkgpcBwuylsOq2kSVOJ5wBPoaEs
# sJkeMcKnEuuu++UKdDHlS0DtsYjN0QnOucvTdSsdvhzKOSjJF3XVqr9f2C945LXT
# 5rxKIHUIEDBcNYU6BKDDH6rfpKOOCSilAgMBAAGjggFGMIIBQjAOBgNVHQ8BAf8E
# BAMCAYYwEAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYEFB6C3w7XjLPXAjSDDtqr
# rWW5r7jsMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMA8GA1UdEwEB/wQFMAMB
# Af8wHwYDVR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb186aGMQwVgYDVR0fBE8wTTBL
# oEmgR4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMv
# TWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggr
# BgEFBQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNS
# b29DZXJBdXRfMjAxMC0wNi0yMy5jcnQwDQYJKoZIhvcNAQEMBQADggIBAENf+N8/
# u+mUjDtc9btoA52RBc0XVDSBMQBMqxu56hXHBwuctUWs1XBqDDMIFCHu9c6Y/UF+
# TN8EIgjnujApKYmHP4f4EM3ARSmlzrpF5ozOJx0BA5FUv1jmpdf/2ZbqpvCxlxv/
# G1R4KjrSmmqPHzs6igw3b7RTbj7BxIS8fOIkwYWQhB2fLjlg+3HSrDGPFIhpIJWV
# amMIR7a72OGonjdf45rspwqIHuynZU4avy9ruB/Rhhbwm+fMb8BMecIaTmkohx/E
# ZZ5GNWcN6oTYW3G2BM3B3YznWkl9t4shP60fMue+2ksdHGWSE8EVTdSmGUdj0jrU
# c46lGVFJISF3/MxcxnlNeP1Khyr+ZzT4Ets/I7mufpaLnLalzMR2zIuhGOAWWswe
# sbjtFzkVUFgDR2SW903I0XKlbPEA6q8epHGJ9roxh85nsEKcBNUw4Scp68KCqSpF
# BaKiyV1skd+l8U50WNePMb9Bzz0OfASal8v5sQG+DW01kN+I+RKUIbM5I50wJjiH
# ymQFNDsbobFx9I95mCEEPU7fUZ3VT/HOUVbkmX7ltIC/eQAu5GO8fu+ceETMybvb
# oxUM4dYNC+PzooUxfmC0DuKRwB21bX9+acuIBkxIm4Ed3O19w1VLoA7UNOUuJ7z6
# NQ2W/+q7cnfOPl2QVL4qlgCblUT2vmQpllV3MIIHIDCCBQigAwIBAgITMwAAAIbn
# cZS5Tf8J+wAAAAAAhjANBgkqhkiG9w0BAQwFADBfMQswCQYDVQQGEwJVUzEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTAwLgYDVQQDEydNaWNyb3NvZnQg
# V2luZG93cyBDb2RlIFNpZ25pbmcgUENBIDIwMjQwHhcNMjUwNTA4MTgyNDUzWhcN
# MjYwNTA2MTgyNDUzWjB0MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMR4wHAYDVQQDExVNaWNyb3NvZnQgQ29ycG9yYXRpb24wggIiMA0GCSqGSIb3
# DQEBAQUAA4ICDwAwggIKAoICAQCkffWVt1N9gK2cozqGbR1wGCUvR9RBe8CyPJxR
# BCdNuD07Q43NQPiX0rSkJoyYurzxnc82BJmk0UKdH4B929bxJkK1pjAN+Wn9Jedb
# ITMAaIP1Wmw60SC0Hs6wXKeRM9nqOTbkBhp2wKVxkDQppnfqZROMn6EtLcgEfpTU
# Qk/IHxaIbxqbDnRLY31LUareoRlUf0tuLNf42ZAgUDyEtVOjri5pe4AVyPsrPuIh
# EHLXzKrpnuqrK6nSfTgsr7b7fwL4xqd13rhG1DS30LK6JfCAVw7HPbD/7m/RQOhp
# +ZMPhlZZfLWvnqu97cmp3j3+NKRFzYCF6U3VNutdON/AhLn4NN0+Sz6Mm6eixBcS
# ARuYwV1K62vUzyTiK252LQg7XSqwUDcdCTXru+2bt9aH8kosQWgDr8i2Xc9jyZUj
# jEwMlUKzxunqz7tQ80OzTSAgz2ykW0o16CTTEV4/Pb/hLWFlPhXph+jJx+MkhT38
# yr3f2uPwVCuP9eMZSuEafKZc+TOX1Gsr2BFIwxdP8ICJTH7MpvwAv4G17so84xNG
# GvRq7TpS9Ly6ubUJ409709Jnos43dD7fXnE5XmRoILvFDUCo3tnt9Zshnx7wfAsg
# +8phXHOd6YiYgTG773s1HGPvMlwZCT+HPFX7W5ziIdNQC22in37/qrQ7wdKg4UMm
# ZIY4wwIDAQABo4IBvjCCAbowDgYDVR0PAQH/BAQDAgeAMB8GA1UdJQQYMBYGCisG
# AQQBgjc9BgEGCCsGAQUFBwMDMAwGA1UdEwEB/wQCMAAwHQYDVR0OBBYEFFCjGj3V
# OqaQ27YLTqVOylBylCiAMFQGA1UdEQRNMEukSTBHMS0wKwYDVQQLEyRNaWNyb3Nv
# ZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxFjAUBgNVBAUTDTIzMDg2NSs1
# MDQ1OTEwHwYDVR0jBBgwFoAUHoLfDteMs9cCNIMO2qutZbmvuOwwagYDVR0fBGMw
# YTBfoF2gW4ZZaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwvTWlj
# cm9zb2Z0JTIwV2luZG93cyUyMENvZGUlMjBTaWduaW5nJTIwUENBJTIwMjAyNC5j
# cmwwdwYIKwYBBQUHAQEEazBpMGcGCCsGAQUFBzAChltodHRwOi8vd3d3Lm1pY3Jv
# c29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFdpbmRvd3MlMjBDb2Rl
# JTIwU2lnbmluZyUyMFBDQSUyMDIwMjQuY3J0MA0GCSqGSIb3DQEBDAUAA4ICAQAM
# OWRf42CxONGV43y2AkPRXmTlBZytzMdgL8Aa6W9w+1UNxP8sSs6YlC9ADqTlehqh
# DVKZjTzRj/7ENx+Lzvu+uc4sVvYfRb4iNYwsj798zooF008RAOVvJ1Zz4hnL13mk
# yW9Pe3OA0Wm824FlnhgrV1N3OHij09S0x4xXv4BGVLL5OVxkiH8+kKquKApvPDod
# c+ZDfzocEwK0ORABs12RXDuoePES8XBRZ/WUCN/BPle7ZGMgYcfPWQ+qREn64GcL
# HvufdK5mYmQlKnazA2CIzvwdTyPwfqTTBeUk0MkHtiZfcE98xXVYlO9J3A7q6K7w
# xSuDrEGheVwRoEbhYOfLp5xN9cE11LLXbLDF2j8MDBTjY/sigH9lESII89vAQmhN
# x2z3/6tvou017ex3pFVb2qEia3OMv/+6Pb3UXbFf0EYshPjTkYIChpYSgZ6ctKZZ
# x7C6PFcztRon+JKsyDbAjjmjNV0VB94wXz5he0VV4Tq7NUQs5SgfCqZqxoXGLuTY
# X9gfp1tMStsJqb/yYPpmKM476KpKVstwoz+vwY+lwfPhcRhpxJvjXV0tt4x57ThO
# /TctTdV5SzuaE8ttOfUWzLCbcveKJ3F/6cBdO6nIMj4W8fp4S2xu45DToWeLb35+
# 608fp/yrVLJw+MXwtop7qDwm+6qb/MYQoy8Tk8XvojGCGwAwghr8AgEBMHYwXzEL
# MAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEwMC4G
# A1UEAxMnTWljcm9zb2Z0IFdpbmRvd3MgQ29kZSBTaWduaW5nIFBDQSAyMDI0AhMz
# AAAAhudxlLlN/wn7AAAAAACGMA0GCWCGSAFlAwQCAQUAoIGoMBkGCSqGSIb3DQEJ
# AzEMBgorBgEEAYI3AgEEMC8GCSqGSIb3DQEJBDEiBCD12p2EXg5HuAOMXy8l2stP
# 0pmptaSGI99pdu8uRzlUuDBaBgorBgEEAYI3AgEMMUwwSqAkgCIATQBpAGMAcgBv
# AHMAbwBmAHQAIABXAGkAbgBkAG8AdwBzoSKAIGh0dHA6Ly93d3cubWljcm9zb2Z0
# LmNvbS93aW5kb3dzMA0GCSqGSIb3DQEBAQUABIICABTZR+z+mpLQ4y8zIm43L2jL
# zuzqM81EgLBJD9G8hjBUErVMlEni25/IU2wHhec+t0E5yrsgAtYaPT9UfzPIG3VR
# GQr7M4DyV19IYuTHRJamR/vi0BrYgdswR/6YZzK4UDgIxpYZjO9z8rnFVY5CKnUL
# ex79/3ygYbGOJBvG82FYAf2AeOiw071xYsUWBCUQSEzFcitJtFXfA2Npa8M/6kaJ
# AhnU+QCNH9t1ccXw/sfOoeT5nj2WBGXewcpHoMvItmTFk/Sew7wFnJoOWmxVt0HN
# Co4U4DUNRKP+1St50QF5Ta64w95WOGs0Qf5WTuHGkdTTbkzWBdsuD9jnzu1iakfe
# uRt6YpcWtcjp+pCe/LtU57Lb/3CMT4QGJOACsuBLrgTGgHgOlzWU5mznI2j14ymq
# eLfcrjyBs0skrU8YyM6Qw24UOhr7dlUn96/9zJpAD7Ocik78NJDCK9R7QraTfgf+
# I0jUzWbspcBvJWWH/Z/jwH/r2m4dloQWVwudu6vKegfYUg6UQBmvMdfgH5JcvKG+
# wY43gSjnLaRpTRwGIulQhCVzhYUgVwNRBxsgaepoiWlGLJFX+dQSIKfAQvBd3Fiz
# EhHIK1sjfgf7wL46GwP8YKQSLaxQhcCH424qN/Ptkownz+pMSm7QubHI0i3qhoWi
# gEm89ssEVk9KqEgxt0VBoYIXsDCCF6wGCisGAQQBgjcDAwExghecMIIXmAYJKoZI
# hvcNAQcCoIIXiTCCF4UCAQMxDzANBglghkgBZQMEAgEFADCCAVoGCyqGSIb3DQEJ
# EAEEoIIBSQSCAUUwggFBAgEBBgorBgEEAYRZCgMBMDEwDQYJYIZIAWUDBAIBBQAE
# IN5SGlFeD05Cm7DoKW+jbtHlFbt+TNCy/16XewugVUu+AgZorgAEB3gYEzIwMjUw
# OTA1MDM1OTUwLjI4MVowBIACAfSggdmkgdYwgdMxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9w
# ZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjM2MDUt
# MDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNl
# oIIR/jCCBygwggUQoAMCAQICEzMAAAH3WCB1BMr7wvQAAQAAAfcwDQYJKoZIhvcN
# AQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQG
# A1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwHhcNMjQwNzI1MTgz
# MTA2WhcNMjUxMDIyMTgzMTA2WjCB0zELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
# c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEtMCsGA1UECxMkTWljcm9zb2Z0IElyZWxhbmQgT3BlcmF0aW9u
# cyBMaW1pdGVkMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046MzYwNS0wNUUwLUQ5
# NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIiMA0G
# CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDQ50dME2ibr+5cpoQo/2s8hORPpDEX
# XW2PMHQ2TVvIOk+sVMeFreHHBJ1NyvxjRreToRCXCrLpE7PjZ7RHl4Nb50KhBqmK
# kMgVQ5ineg26rBf/F6kBMSRjXszJcXHqtBbY1xZQlbdCjYC4nQc61uVKki1Bk8aY
# ecaqS38MHjkXDGTpWhK/E1xAqEoROS7Ou3xToNFxxCbUV2GY8qAPOBx8M8zmj4af
# NuIy7rLTr0DgQeYsyaR5xKRW8GZxnxWfMUdMOQYt2mcNXkVeNU5sCBtIzRyephIZ
# 9GntUYcFGrKixy9HhtxD4JX2kONsnpLmtmfW4DyFGGPT0ezfcdF6+3ihYBVgYi2A
# Swb4GsJhumBYwMQhWcCA9kSI8BojzAEZ6YTh94SS7PtMDCCREFxTMuBDi68+pEPU
# D4mS3br6kOpZhKfQwDyPTNpxCT2r8C9yI9cP0i3Z7P6aoTOAVFGwkYu1x/0eSy8r
# wmx3ojnMVKGWqLlunN/Vjg06I06HlDBbWki8DmKuVqXuoWGQB555mqainz643Flf
# EUJAbdHezmldbz0WIKH2uZetWo4LCBxcUglABCSWUqwj5Qmoar2uZEAEnPmUcpMV
# iYXBwznYpZaM3HfPqh3DPaH6zFrF7BOh70aq0PHf9pT7Ko1FwHzDS1JdR/7KU3i6
# TnEcSkunH5k02wIDAQABo4IBSTCCAUUwHQYDVR0OBBYEFN9GpDM/eb09la4t/Wnz
# +Z4V+SaYMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRY
# MFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01p
# Y3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggrBgEF
# BQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9w
# a2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAo
# MSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwDgYD
# VR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUAA4ICAQA3RqNp8gt4vpJAgwgwBczV
# B3rFqhyLaY6ulHy8pbLJOwvdvzcDtcYuIBtDFOuqde9VZZ42y3lhAPyxo75ROA4s
# l1N19QAOEtegr5GXCN+d2KYglP0wf21RhcvMlcqFkzT2i4/A2yufxg4sil0CLlM/
# I3wKXXU4ZlKU/2vwme+iZbTQCgng+X2uWDQbmVxCScBeodr2dB1anVnFeo137Qmw
# qaVHy1wA1ffcKUz02doKUkTEtAeIp4dRRa2rIsyXrlNbrBEzteUXtj49OcLx241a
# fi4ueD4439nf0Y7qoGPsgRnGirijdq8SH1trjdRTpODNVloGbxVoDTBLBR7+mqlM
# 5gVY3rZcveCX8kLanN8g/E/rpd9EsjFp+MFVebwpUOfZwwv0i9ErTaz3jVjn5FHi
# BIA6EuJBDoDTdU1G6n6ykxrST5dM8CL7ZowfnFrVmNv8ry71/0zTlTT9tQwlckM/
# 77KxakltVEOIcbuzNpxr6vceJQ+NAnJCXY2I5xhMZX8NwussIErbMbnTcUZvTg3k
# p/XReADAVpeWh3kH14qH3k+dcrHYs0GAvAbzlqeWGEbHEFDmYWwkaQGfQ9k+0DNn
# J+v3qrHOmnakf0MklyMoIOsyZnOJdrOlrlVU3foI7WQNTgAGRJhNc4zxGYle5Cbu
# ZQXdtaaP6GMAlvinPqFPlTCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkAAAAA
# ABUwDQYJKoZIhvcNAQELBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRlIEF1
# dGhvcml0eSAyMDEwMB4XDTIxMDkzMDE4MjIyNVoXDTMwMDkzMDE4MzIyNVowfDEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
# bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwggIiMA0GCSqGSIb3DQEBAQUAA4IC
# DwAwggIKAoICAQDk4aZM57RyIQt5osvXJHm9DtWC0/3unAcH0qlsTnXIyjVX9gF/
# bErg4r25PhdgM/9cT8dm95VTcVrifkpa/rg2Z4VGIwy1jRPPdzLAEBjoYH1qUoNE
# t6aORmsHFPPFdvWGUNzBRMhxXFExN6AKOG6N7dcP2CZTfDlhAnrEqv1yaa8dq6z2
# Nr41JmTamDu6GnszrYBbfowQHJ1S/rboYiXcag/PXfT+jlPP1uyFVk3v3byNpOOR
# j7I5LFGc6XBpDco2LXCOMcg1KL3jtIckw+DJj361VI/c+gVVmG1oO5pGve2krnop
# N6zL64NF50ZuyjLVwIYwXE8s4mKyzbnijYjklqwBSru+cakXW2dg3viSkR4dPf0g
# z3N9QZpGdc3EXzTdEonW/aUgfX782Z5F37ZyL9t9X4C626p+Nuw2TPYrbqgSUei/
# BQOj0XOmTTd0lBw0gg/wEPK3Rxjtp+iZfD9M269ewvPV2HM9Q07BMzlMjgK8Qmgu
# EOqEUUbi0b1qGFphAXPKZ6Je1yh2AuIzGHLXpyDwwvoSCtdjbwzJNmSLW6CmgyFd
# XzB0kZSU2LlQ+QuJYfM2BjUYhEfb3BvR/bLUHMVr9lxSUV0S2yW6r1AFemzFER1y
# 7435UsSFF5PAPBXbGjfHCBUYP3irRbb1Hode2o+eFnJpxq57t7c+auIurQIDAQAB
# o4IB3TCCAdkwEgYJKwYBBAGCNxUBBAUCAwEAATAjBgkrBgEEAYI3FQIEFgQUKqdS
# /mTEmr6CkTxGNSnPEP8vBO4wHQYDVR0OBBYEFJ+nFV0AXmJdg/Tl0mWnG1M1Gely
# MFwGA1UdIARVMFMwUQYMKwYBBAGCN0yDfQEBMEEwPwYIKwYBBQUHAgEWM2h0dHA6
# Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTAT
# BgNVHSUEDDAKBggrBgEFBQcDCDAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTAL
# BgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbLj+ii
# XGJo0T2UkFvXzpoYxDBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1pY3Jv
# c29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0y
# My5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNy
# dDANBgkqhkiG9w0BAQsFAAOCAgEAnVV9/Cqt4SwfZwExJFvhnnJL/Klv6lwUtj5O
# R2R4sQaTlz0xM7U518JxNj/aZGx80HU5bbsPMeTCj/ts0aGUGCLu6WZnOlNN3Zi6
# th542DYunKmCVgADsAW+iehp4LoJ7nvfam++Kctu2D9IdQHZGN5tggz1bSNU5HhT
# dSRXud2f8449xvNo32X2pFaq95W2KFUn0CS9QKC/GbYSEhFdPSfgQJY4rPf5KYnD
# vBewVIVCs/wMnosZiefwC2qBwoEZQhlSdYo2wh3DYXMuLGt7bj8sCXgU6ZGyqVvf
# SaN0DLzskYDSPeZKPmY7T7uG+jIa2Zb0j/aRAfbOxnT99kxybxCrdTDFNLB62FD+
# CljdQDzHVG2dY3RILLFORy3BFARxv2T5JL5zbcqOCb2zAVdJVGTZc9d/HltEAY5a
# GZFrDZ+kKNxnGSgkujhLmm77IVRrakURR6nxt67I6IleT53S0Ex2tVdUCbFpAUR+
# fKFhbHP+CrvsQWY9af3LwUFJfn6Tvsv4O+S3Fb+0zj6lMVGEvL8CwYKiexcdFYmN
# cP7ntdAoGokLjzbaukz5m/8K6TT4JDVnK+ANuOaMmdbhIurwJ0I9JZTmdHRbatGe
# Pu1+oDEzfbzL6Xu/OHBE0ZDxyKs6ijoIYn/ZcGNTTY3ugm2lBRDBcQZqELQdVTNY
# s6FwZvKhggNZMIICQQIBATCCAQGhgdmkgdYwgdMxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9w
# ZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjM2MDUt
# MDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNl
# oiMKAQEwBwYFKw4DAhoDFQBvbwoMb/Fds0GOYzv+erDduCsQ5qCBgzCBgKR+MHwx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA7GRb
# FzAiGA8yMDI1MDkwNDE4MzgxNVoYDzIwMjUwOTA1MTgzODE1WjB3MD0GCisGAQQB
# hFkKBAExLzAtMAoCBQDsZFsXAgEAMAoCAQACAhmsAgH/MAcCAQACAhJ6MAoCBQDs
# ZayXAgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMH
# oSChCjAIAgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBAHe1sbm9MK8oT9mOhm8s
# JhVDEWpN21USdw4d87oHxR7GMDxJ+N7xXHD9ezf81uQvIDWFD/zkAOoUH323SWE1
# 2JomXNckk56jePvJtepSd0imKxTYYnMU6tYE0LDr5Yrq5cn72tUXVbhxKMJa9j+r
# RYk8OA9zkNpN7tWfOiN4rMWE9pIyBk6wroap6XQBsCeBZBEzIUsejLU+PSNWeISX
# W+1YpOuDvNTVyJGaz67dZVrmH24ZhlQGW9c/qlXFp0pyOt3pkZDUDTmpUpkuUxdZ
# 0aq0q8N1VPMxzC0P5KepOS5nIv/flLuksIdQCtSiagzHmQaq3d1NSIIfRoLYD6un
# BbsxggQNMIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAIT
# MwAAAfdYIHUEyvvC9AABAAAB9zANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcN
# AQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCCgFt+KU7h2G3ZHlFJA
# MpXr4YZeGlnJL1877aewN07fhDCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0E
# ICHamNprdxrR5xi6G7rS5gc/8gqc9t51tVAnlKggflniMIGYMIGApH4wfDELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAH3WCB1BMr7wvQAAQAAAfcwIgQg
# k8QoULMVgSeE/GrAz0MdUMwnEWUwj1GV/+Vk3cv5pqkwDQYJKoZIhvcNAQELBQAE
# ggIAOrYqcV1UNLsvlVqBOL1cdbtIcuqFW9JvCswE0LMqHm25ZONA0gHfcmk8cXBy
# aR2S3qVQBQME8qX4D1tWvrguLCTJWMNo/FluurUYegBJ8WyhwPtnmBGRUMyb5qWM
# 47dJMznxM1TpJOTzcgCHLBNlFyogiaMEHlMvio9Vgf8LT4KrcczkpLasvOWckoB+
# csBCNLG9XFRWO+yoluChIVglr9EkZVmuwDSXZ+S6AUoOlQKbvSrRtmICjQDmA2Dx
# bHm9ISZVjUVzqItVpMSnVkdsDIZbGaNs/yQk0/hwqmNmRQZXIVv28dOdTcxdb8d4
# mX7l2CC2GqtAEyHh2aZDRaJvM/1DPptk9pJ9xqosjLANdOQvScI/5DExK7m2+znk
# RtQ3TfUsw2l/VY4MAi1tVJLVoRwb6sVVnLDsQpu5vPDwAIfC9HPgOnjdcK7X6G7i
# Q5mPmXKk69XReMLukQH6ucXHenhKBysAfwkqS9FSpNllvqhATMruNfGR+EramB9w
# yE4WpxImVbUNEnzVBRl5ue31siCtGops8InblJvtMsp6iJy+fXLlJF3Pn0b+Zmg6
# MAWQMiuCGdFlSGW76iuDgl5Kn39IZpCnGfrKoeKm4u17ei+429ZtmsLuHxahif8p
# BnRPI70Qtwh79qfGv3RB/TnJLc24lFCp88j18a247OZb5/o=
# SIG # End signature block
