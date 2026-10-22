param([Parameter(Mandatory=$true)][string]$Directory)
$ErrorActionPreference='Stop'
$target=(Resolve-Path -LiteralPath $Directory).Path
if (!(Test-Path -LiteralPath $target -PathType Container)) { throw 'Recovery directory required' }
if ((Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Recovery directory cannot be a link' }
$security=New-Object Security.AccessControl.DirectorySecurity
$security.SetAccessRuleProtection($true,$false)
$identity=[Security.Principal.WindowsIdentity]::GetCurrent().User
foreach ($sid in @($identity,[Security.Principal.SecurityIdentifier]::new('S-1-5-18'))) {
  $security.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow'))
}
Set-Acl -LiteralPath $target -AclObject $security
