# Creates android/cafein-upload-keystore.p12 via GUI password prompt.
# Does NOT touch existing .jks files. Never prints the password.

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName Microsoft.VisualBasic
Add-Type -AssemblyName System.Windows.Forms

$androidDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$statusFile = Join-Path $androidDir "create-keystore-status.txt"
$p12Path = Join-Path $androidDir "cafein-upload-keystore.p12"
$propsPath = Join-Path $androidDir "key.properties"
$keytool = "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe"
if (-not (Test-Path $keytool)) {
    $cmd = Get-Command keytool -ErrorAction SilentlyContinue
    if ($cmd) { $keytool = $cmd.Source }
}
if (-not (Test-Path $keytool)) {
    throw "keytool.exe not found. Install Android Studio JBR or add keytool to PATH."
}

function Write-Status([int]$code, [string]$msg) {
    Set-Content -Path $statusFile -Value "$code`n$msg" -Encoding UTF8
}

try {
    if (Test-Path $p12Path) {
        Write-Status 2 "P12 already exists"
        [System.Windows.Forms.MessageBox]::Show(
            "cafein-upload-keystore.p12 already exists. Not overwriting.",
            "CAFEIN",
            "OK",
            "Warning"
        ) | Out-Null
        exit 2
    }

    $pass1 = [Microsoft.VisualBasic.Interaction]::InputBox(
        "Enter NEW store/key password (same value for both)." + [char]13 + [char]10 +
        "This creates android\cafein-upload-keystore.p12" + [char]13 + [char]10 +
        "Existing .jks files are NOT modified.",
        "CAFEIN upload keystore",
        ""
    )
    if ([string]::IsNullOrEmpty($pass1)) {
        Write-Status 3 "cancelled or empty"
        exit 3
    }

    $pass2 = [Microsoft.VisualBasic.Interaction]::InputBox(
        "Confirm the same password:",
        "CAFEIN upload keystore",
        ""
    )
    if ($pass1 -cne $pass2) {
        Write-Status 4 "passwords do not match"
        [System.Windows.Forms.MessageBox]::Show(
            "Passwords do not match. Nothing was created.",
            "CAFEIN",
            "OK",
            "Error"
        ) | Out-Null
        $pass1 = $null
        $pass2 = $null
        exit 4
    }
    $pass2 = $null
    $env:CAFEIN_KS_PASS = $pass1
    $pass1 = $null

    $dname = "CN=CAFEIN Upload, OU=Mobile, O=Baekson, L=Seoul, ST=Seoul, C=KR"

    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $gen = & $keytool -genkeypair `
        -keystore $p12Path `
        -storetype PKCS12 `
        -alias upload `
        -keyalg RSA `
        -keysize 2048 `
        -validity 10000 `
        -dname $dname `
        -storepass:env CAFEIN_KS_PASS `
        -keypass:env CAFEIN_KS_PASS 2>&1
    $genCode = $LASTEXITCODE
    $ErrorActionPreference = $prevEap

    if (-not (Test-Path $p12Path)) {
        throw "keytool -genkeypair failed (exit=$genCode): $gen"
    }

    $ErrorActionPreference = "Continue"
    $listOut = & $keytool -list -v `
        -keystore $p12Path `
        -storetype PKCS12 `
        -storepass:env CAFEIN_KS_PASS `
        -alias upload 2>&1
    $listCode = $LASTEXITCODE
    $ErrorActionPreference = $prevEap

    if ($listCode -ne 0) { throw "keytool -list failed (exit=$listCode): $listOut" }

    $shaLine = ($listOut | Select-String -Pattern "SHA256:").Line
    if (-not $shaLine) { $shaLine = "SHA256: (not found)" }

    $pass = $env:CAFEIN_KS_PASS
    $newBody = @"
# CAFEIN Play upload signing — local only. Do NOT commit.
# storeFile is relative to android/app/
storePassword=$pass
keyPassword=$pass
keyAlias=upload
storeFile=../cafein-upload-keystore.p12
"@
    $pass = $null
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($propsPath, $newBody.TrimEnd() + "`n", $utf8NoBom)

    Write-Status 0 $shaLine

    [System.Windows.Forms.MessageBox]::Show(
        "Keystore created successfully.`n`n$shaLine`n`nkey.properties updated.`nPasswords were not shown.",
        "CAFEIN",
        "OK",
        "Information"
    ) | Out-Null
}
catch {
    Write-Status 1 $_.Exception.Message
    [System.Windows.Forms.MessageBox]::Show(
        "Failed: $($_.Exception.Message)",
        "CAFEIN",
        "OK",
        "Error"
    ) | Out-Null
    exit 1
}
finally {
    Remove-Item Env:CAFEIN_KS_PASS -ErrorAction SilentlyContinue
}

exit 0
