# Offline stand-in with the official installer's parameter order.
# ProxyCredential is a string here so a regression fails without a password prompt.
param(
    [string]$ScoopDir,
    [string]$ScoopGlobalDir,
    [string]$ScoopCacheDir,
    [switch]$NoProxy,
    [uri]$Proxy,
    [string]$ProxyCredential,
    [switch]$ProxyUseDefaultCredentials,
    [switch]$RunAsAdmin
)

if ($ScoopDir -ne 'D:\Test Apps\Scoop' -or $ScoopGlobalDir -ne 'D:\Test Apps\ScoopGlobal') {
    throw 'Installer received incorrect directory parameters.'
}
if ($ScoopCacheDir -or $NoProxy -or $Proxy -or $ProxyCredential -or $ProxyUseDefaultCredentials) {
    throw 'Installer received unintended cache or proxy parameters.'
}

Write-Output ([pscustomobject]@{
    Root = $ScoopDir
    GlobalRoot = $ScoopGlobalDir
    RunAsAdmin = [bool]$RunAsAdmin
})
exit 0
