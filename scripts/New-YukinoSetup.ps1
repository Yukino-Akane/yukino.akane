param(
    [Parameter(Mandatory = $true)]
    [string]$MsixPath,
    [Parameter(Mandatory = $true)]
    [string]$CertificatePath,
    [Parameter(Mandatory = $true)]
    [string]$ChecksumPath,
    [Parameter(Mandatory = $true)]
    [string]$InstallerPath,
    [string]$OutputPath = "",
    [string]$ProductName = "Yukino"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Resolve-RequiredFile([string]$Path, [string]$Description) {
    $resolved = Resolve-Path -LiteralPath $Path -ErrorAction Stop
    if (-not $resolved) {
        throw "Cannot resolve $Description`: $Path"
    }
    return $resolved.Path
}

$msix = Resolve-RequiredFile -Path $MsixPath -Description "MSIX package"
$certificate = Resolve-RequiredFile -Path $CertificatePath -Description "certificate"
$checksum = Resolve-RequiredFile -Path $ChecksumPath -Description "checksum file"
$installer = Resolve-RequiredFile -Path $InstallerPath -Description "installer script"

if ((Split-Path -Leaf $installer) -ne "Install-YukinoRelease.ps1") {
    throw "Setup must embed Install-YukinoRelease.ps1, got: $installer"
}

$msixName = Split-Path -Leaf $msix
$versionMatch = [regex]::Match($msixName, "^(?<package>.+)_(?<version>\d+\.\d+\.\d+\.\d+)_x64\.msix$")
if (-not $versionMatch.Success) {
    throw "Cannot infer package version from MSIX name: $msixName"
}

$version = $versionMatch.Groups["version"].Value
$output = if ($OutputPath) {
    $OutputPath
}
else {
    Join-Path (Split-Path -Parent $msix) ("Yukino-Setup-{0}.exe" -f $version)
}

$outputParent = Split-Path -Parent $output
if ($outputParent -and -not (Test-Path -LiteralPath $outputParent)) {
    New-Item -ItemType Directory -Path $outputParent | Out-Null
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("YukinoSetupBuild-" + [guid]::NewGuid().ToString("N"))
$payloadDir = Join-Path $tempRoot "payload"
$bootstrap = Join-Path $tempRoot "YukinoSetupBootstrap.exe"
$payloadZip = Join-Path $tempRoot "payload.zip"

New-Item -ItemType Directory -Path $payloadDir | Out-Null

try {
    Copy-Item -LiteralPath $msix -Destination (Join-Path $payloadDir $msixName) -Force
    Copy-Item -LiteralPath $certificate -Destination (Join-Path $payloadDir (Split-Path -Leaf $certificate)) -Force
    Copy-Item -LiteralPath $checksum -Destination (Join-Path $payloadDir "SHA256SUMS.txt") -Force
    Copy-Item -LiteralPath $installer -Destination (Join-Path $payloadDir "Install-YukinoRelease.ps1") -Force

    $source = @"
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Text;
using System.Windows.Forms;

public static class YukinoSetup
{
    private static readonly byte[] Marker = Encoding.ASCII.GetBytes("YUKINO_SETUP_PAYLOAD_V1");

    [STAThread]
    public static int Main()
    {
        string workDir = Path.Combine(Path.GetTempPath(), "YukinoSetup-" + Guid.NewGuid().ToString("N"));
        string zipPath = Path.Combine(workDir, "payload.zip");

        try
        {
            Directory.CreateDirectory(workDir);
            ExtractPayload(zipPath);
            ZipFile.ExtractToDirectory(zipPath, workDir);

            string installer = Path.Combine(workDir, "Install-YukinoRelease.ps1");
            string powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe");

            ProcessStartInfo startInfo = new ProcessStartInfo();
            startInfo.FileName = powershell;
            startInfo.WorkingDirectory = workDir;
            startInfo.UseShellExecute = true;
            startInfo.Verb = "runas";
            startInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + installer + "\"";

            Process process = Process.Start(startInfo);
            if (process == null)
            {
                MessageBox.Show("Yukino setup could not start PowerShell.", "Yukino Setup", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }

            process.WaitForExit();
            return process.ExitCode;
        }
        catch (Win32Exception ex)
        {
            MessageBox.Show("Yukino setup could not start: " + ex.Message, "Yukino Setup", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        catch (Exception ex)
        {
            MessageBox.Show("Yukino setup failed: " + ex.Message, "Yukino Setup", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        finally
        {
            try
            {
                if (Directory.Exists(workDir))
                {
                    Directory.Delete(workDir, true);
                }
            }
            catch
            {
            }
        }
    }

    private static void ExtractPayload(string zipPath)
    {
        string selfPath = Process.GetCurrentProcess().MainModule.FileName;
        using (FileStream stream = File.OpenRead(selfPath))
        {
            if (stream.Length < Marker.Length + sizeof(long))
            {
                throw new InvalidDataException("Setup payload is missing.");
            }

            stream.Seek(-Marker.Length, SeekOrigin.End);
            byte[] marker = new byte[Marker.Length];
            ReadExactly(stream, marker, marker.Length);
            for (int index = 0; index < Marker.Length; index++)
            {
                if (marker[index] != Marker[index])
                {
                    throw new InvalidDataException("Setup payload marker is invalid.");
                }
            }

            stream.Seek(-(Marker.Length + sizeof(long)), SeekOrigin.End);
            byte[] lengthBytes = new byte[sizeof(long)];
            ReadExactly(stream, lengthBytes, lengthBytes.Length);
            long payloadLength = BitConverter.ToInt64(lengthBytes, 0);
            long payloadOffset = stream.Length - Marker.Length - sizeof(long) - payloadLength;
            if (payloadLength <= 0 || payloadOffset < 0)
            {
                throw new InvalidDataException("Setup payload length is invalid.");
            }

            stream.Seek(payloadOffset, SeekOrigin.Begin);
            using (FileStream output = File.Create(zipPath))
            {
                byte[] buffer = new byte[1024 * 1024];
                long remaining = payloadLength;
                while (remaining > 0)
                {
                    int toRead = remaining > buffer.Length ? buffer.Length : (int)remaining;
                    int read = stream.Read(buffer, 0, toRead);
                    if (read <= 0)
                    {
                        throw new EndOfStreamException("Unexpected end of setup payload.");
                    }
                    output.Write(buffer, 0, read);
                    remaining -= read;
                }
            }
        }
    }

    private static void ReadExactly(Stream stream, byte[] buffer, int count)
    {
        int offset = 0;
        while (offset < count)
        {
            int read = stream.Read(buffer, offset, count - offset);
            if (read <= 0)
            {
                throw new EndOfStreamException();
            }
            offset += read;
        }
    }
}
"@

    Add-Type -AssemblyName Microsoft.CSharp

    $compilerParameters = New-Object System.CodeDom.Compiler.CompilerParameters
    $compilerParameters.GenerateExecutable = $true
    $compilerParameters.OutputAssembly = $bootstrap
    $compilerParameters.CompilerOptions = "/target:winexe /platform:x64"
    $compilerParameters.ReferencedAssemblies.Add("System.dll") | Out-Null
    $compilerParameters.ReferencedAssemblies.Add("System.Windows.Forms.dll") | Out-Null
    $compilerParameters.ReferencedAssemblies.Add("System.IO.Compression.dll") | Out-Null
    $compilerParameters.ReferencedAssemblies.Add("System.IO.Compression.FileSystem.dll") | Out-Null

    $provider = New-Object Microsoft.CSharp.CSharpCodeProvider
    try {
        $compileResults = $provider.CompileAssemblyFromSource($compilerParameters, $source)
        if ($compileResults.Errors.HasErrors) {
            $errors = @($compileResults.Errors | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
            throw "Setup bootstrap compilation failed:$([Environment]::NewLine)$errors"
        }
    }
    finally {
        $provider.Dispose()
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($payloadDir, $payloadZip)

    $markerBytes = [Text.Encoding]::ASCII.GetBytes("YUKINO_SETUP_PAYLOAD_V1")
    $payloadLengthBytes = [BitConverter]::GetBytes((Get-Item -LiteralPath $payloadZip).Length)

    Copy-Item -LiteralPath $bootstrap -Destination $output -Force
    $outputStream = [IO.File]::Open($output, [IO.FileMode]::Append, [IO.FileAccess]::Write)
    try {
        $payloadStream = [IO.File]::OpenRead($payloadZip)
        try {
            $payloadStream.CopyTo($outputStream)
        }
        finally {
            $payloadStream.Dispose()
        }

        $outputStream.Write($payloadLengthBytes, 0, $payloadLengthBytes.Length)
        $outputStream.Write($markerBytes, 0, $markerBytes.Length)
    }
    finally {
        $outputStream.Dispose()
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        for ($attempt = 1; $attempt -le 5; $attempt++) {
            try {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction Stop
                break
            }
            catch {
                if ($attempt -eq 5) {
                    Write-Warning "Could not remove temporary setup build directory: $tempRoot"
                }
                else {
                    Start-Sleep -Milliseconds (150 * $attempt)
                }
            }
        }
    }
}

if (-not (Test-Path -LiteralPath $output)) {
    throw "Setup executable was not created: $output"
}

Write-Host "Created setup installer: $output"
