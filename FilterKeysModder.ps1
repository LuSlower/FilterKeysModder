# Check administrator privileges
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process powershell "-File `"$PSCommandPath`"" -Verb RunAs
    exit
}


Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Console
{
    param ([Switch]$Show,[Switch]$Hide)
    if (-not ("Console.Window" -as [type])) { 

        Add-Type -Name Window -Namespace Console -MemberDefinition '
        [DllImport("Kernel32.dll")]
        public static extern IntPtr GetConsoleWindow();

        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
        '
    }

    if ($Show)
    {
        $consolePtr = [Console.Window]::GetConsoleWindow()

        $null = [Console.Window]::ShowWindow($consolePtr, 5)
    }

    if ($Hide)
    {
        $consolePtr = [Console.Window]::GetConsoleWindow()
        #0 hide
        $null = [Console.Window]::ShowWindow($consolePtr, 0)
    }
}

# crear la clave de registro si no existe
$global:regPath = "HKCU:\Control Panel\Accessibility\Keyboard Response"

if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}

# establecer flags (banderas)
function Set-Flags {
    param (
        [bool]$enable
    )
    $flag = if ($enable) { 1 } else { 0 }
    Set-ItemProperty -Path $regPath -Name "Flags" -Value $flag
}

# establecer los parámetros de las Teclas de Filtro
function Set-FilterKeys-Reg {
    param (
        [int]$bounceTime,    # Intervalo de tiempo para BounceKeys (ms)
        [int]$delayTime,     # Retardo de tiempo para SlowKeys (ms)
        [int]$repeatRate,    # Frecuencia de repetición para RepeatKeys (ms)
        [int]$repeatDelay    # Retardo de repetición para RepeatKeys (ms)
    )
    Set-ItemProperty -path $regPath -name "BounceTime" -value $bounceTime
    Set-ItemProperty -path $regPath -name "DelayBeforeAcceptance" -value $delayTime
    Set-ItemProperty -path $regPath -name "AutoRepeatRate" -value $repeatRate
    Set-ItemProperty -path $regPath -name "AutoRepeatDelay" -value $repeatDelay
}

# definir SystemParametersInfo
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class NativeMethods {
    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = false)]
    public static extern int SystemParametersInfo(uint uiAction, uint uiParam, IntPtr pvParam, uint fWinIni);

    public const uint SPI_SETFILTERKEYS = 0x0033;
    public const uint SPIF_UPDATEINIFILE = 0x01;
    public const uint SPIF_SENDCHANGE = 0x02;
}
"@

# definir la estructura FILTERKEYS
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential)]
public struct FILTERKEYS {
    public int cbSize;
    public int dwFlags;
    public int iWaitMSec;
    public int iDelayMSec;
    public int iRepeatMSec;
    public int iBounceMSec;
}
"@

# establecer FilterKeys
function Set-FilterKeys {
    param (
        [bool]$enable,
        [int]$bounceTime,
        [int]$delayTime,
        [int]$repeatRate,
        [int]$repeatDelay
    )
    $filterKeys = New-Object FILTERKEYS
    $filterKeys.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($filterKeys)
    if ($enable) {
        $filterKeys.dwFlags = 0x00000001 -bor 0x00000002 # FKF_FILTERKEYSON | FKF_AVAILABLE
    } else {
        $filterKeys.dwFlags = 0x00000000 # FKF_FILTERKEYSOFF
    }
    $filterKeys.iBounceMSec = $bounceTime
    $filterKeys.iDelayMSec = $repeatDelay
    $filterKeys.iRepeatMSec = $repeatRate
    $filterKeys.iWaitMSec = $delayTime

    $size = [System.Runtime.InteropServices.Marshal]::SizeOf($filterKeys)
    $pFilterKeys = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($size)
    [System.Runtime.InteropServices.Marshal]::StructureToPtr($filterKeys, $pFilterKeys, $true)

    $success = [NativeMethods]::SystemParametersInfo([NativeMethods]::SPI_SETFILTERKEYS, $size, $pFilterKeys, [NativeMethods]::SPIF_UPDATEINIFILE -bor [NativeMethods]::SPIF_SENDCHANGE)

    [System.Runtime.InteropServices.Marshal]::FreeHGlobal($pFilterKeys)

    if ($success) {
        [System.Windows.Forms.MessageBox]::Show("Filter keys updated", "Info", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    } else {
        [System.Windows.Forms.MessageBox]::Show("Error updating Filter Keys", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function Get-RegistryValues {
    param (
        [string]$regPath
    )

    # Obtener los valores del registro con manejo de errores
    try {
        $values = Get-ItemProperty -Path $regPath -ErrorAction Stop

        # Asignar los valores a las variables, o $null si no están presentes
        $BounceTime = if ($values.PSObject.Properties["BounceTime"]) { $values.BounceTime } else { $null }
        $DelayBeforeAcceptance = if ($values.PSObject.Properties["DelayBeforeAcceptance"]) { $values.DelayBeforeAcceptance } else { $null }
        $AutoRepeatDelay = if ($values.PSObject.Properties["AutoRepeatDelay"]) { $values.AutoRepeatDelay } else { $null }
        $AutoRepeatRate = if ($values.PSObject.Properties["AutoRepeatRate"]) { $values.AutoRepeatRate } else { $null }
        $Flags = if ($values.PSObject.Properties["Flags"]) { $values.Flags } else { $null }

        return @{
            BounceTime = $BounceTime
            DelayBeforeAcceptance = $DelayBeforeAcceptance
            AutoRepeatDelay = $AutoRepeatDelay
            AutoRepeatRate = $AutoRepeatRate
            Flags = $Flags
        }
    } catch {
        return @{
            BounceTime = $null
            DelayBeforeAcceptance = $null
            AutoRepeatDelay = $null
            AutoRepeatRate = $null
            Flags = $null
        }
    }
}

function Update-Values{
    $Values = Get-RegistryValues -regPath $regPath
    if ($Values.Flags -ne $null) {
        $chkEnable.Checked = $true
    } else {
        $chkEnable.Checked = $false
    }
    $txtBounceTime.Text = $Values.BounceTime
    $txtDelayTime.Text = $Values.DelayBeforeAcceptance
    $txtRepeatDelay.Text = $Values.AutoRepeatDelay
    $txtRepeatRate.Text = $Values.AutoRepeatRate
}

# ocultar consola, crear el form
Console -Hide
[System.Windows.Forms.Application]::EnableVisualStyles();
$form = New-Object System.Windows.Forms.Form
$form.ClientSize = New-Object System.Drawing.Size(180, 185)
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.Text = "FilterKeysModder"
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.KeyPreview = $true
$form.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::F5) {
        Update-Values
    }
})

$form.Add_Paint({
    param (
        [object]$sender,
        [System.Windows.Forms.PaintEventArgs]$e
    )
    $rect = New-Object System.Drawing.Rectangle(0, 0, $sender.Width, $sender.Height)
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $rect,
        [System.Drawing.Color]::FromArgb(44, 44, 44),   # Color negro
        [System.Drawing.Color]::FromArgb(99, 99, 99),# Color gris oscuro
        [System.Drawing.Drawing2D.LinearGradientMode]::Vertical
    )
    $e.Graphics.FillRectangle($brush, $rect)
})


# Obtener los valores
$Values = Get-RegistryValues -regPath $regPath

# FilterKeyssOn
$chkEnable = New-Object System.Windows.Forms.CheckBox
$chkEnable.Location = New-Object System.Drawing.Point(50, 10)
$chkEnable.Text = "On FilterKeys"
$chkEnable.ForeColor = [System.Drawing.Color]::White
$chkEnable.BackColor = [System.Drawing.Color]::Transparent
$chkEnable.AutoSize = $true

if ($Values.Flags -ne $null) {
    $chkEnable.Checked = $true
}

$form.Controls.Add($chkEnable)

# BounceTime
$lblBounceTime = New-Object System.Windows.Forms.Label
$lblBounceTime.Location = New-Object System.Drawing.Point(12, 40)
$lblBounceTime.Text = "BounceTime (ms):"
$lblBounceTime.ForeColor = [System.Drawing.Color]::White
$lblBounceTime.BackColor = [System.Drawing.Color]::Transparent
$form.Controls.Add($lblBounceTime)

$txtBounceTime = New-Object System.Windows.Forms.TextBox
$txtBounceTime.Location = New-Object System.Drawing.Point(115, 38)
$txtBounceTime.Width = 50
$txtBounceTime.Text = $Values.BounceTime
$txtBounceTime.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtBounceTime.BackColor = [System.Drawing.Color]::FromArgb(44, 44, 44)
$txtBounceTime.ForeColor = [System.Drawing.Color]::White
$form.Controls.Add($txtBounceTime)

# DelayTime
$lblDelayTime = New-Object System.Windows.Forms.Label
$lblDelayTime.Size = New-Object System.Drawing.Size(90, 15)
$lblDelayTime.Location = New-Object System.Drawing.Point(20, 70)
$lblDelayTime.Text = "DelayTime (ms):"
$lblDelayTime.ForeColor = [System.Drawing.Color]::White
$lblDelayTime.BackColor = [System.Drawing.Color]::Transparent
$form.Controls.Add($lblDelayTime)

$txtDelayTime = New-Object System.Windows.Forms.TextBox
$txtDelayTime.Location = New-Object System.Drawing.Point(115, 68)
$txtDelayTime.Width = 50
$txtDelayTime.Text = $Values.DelayBeforeAcceptance
$txtDelayTime.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtDelayTime.BackColor = [System.Drawing.Color]::FromArgb(44, 44, 44)
$txtDelayTime.ForeColor = [System.Drawing.Color]::White
$form.Controls.Add($txtDelayTime)

# RepeatDelay
$lblRepeatDelay = New-Object System.Windows.Forms.Label
$lblRepeatDelay.Location = New-Object System.Drawing.Point(10, 100)
$lblRepeatDelay.Text = "RepeatDelay (ms):"
$lblRepeatDelay.ForeColor = [System.Drawing.Color]::White
$lblRepeatDelay.BackColor = [System.Drawing.Color]::Transparent
$form.Controls.Add($lblRepeatDelay)

$txtRepeatDelay = New-Object System.Windows.Forms.TextBox
$txtRepeatDelay.Location = New-Object System.Drawing.Point(115, 98)
$txtRepeatDelay.Width = 50
$txtRepeatDelay.Text = $Values.AutoRepeatDelay
$txtRepeatDelay.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtRepeatDelay.BackColor = [System.Drawing.Color]::FromArgb(44, 44, 44)
$txtRepeatDelay.ForeColor = [System.Drawing.Color]::White
$form.Controls.Add($txtRepeatDelay)

# RepeatRate
$lblRepeatRate = New-Object System.Windows.Forms.Label
$lblRepeatRate.Location = New-Object System.Drawing.Point(15, 130)
$lblRepeatRate.Text = "RepeatRate (ms):"
$lblRepeatRate.ForeColor = [System.Drawing.Color]::White
$lblRepeatRate.BackColor = [System.Drawing.Color]::Transparent
$form.Controls.Add($lblRepeatRate)

$txtRepeatRate = New-Object System.Windows.Forms.TextBox
$txtRepeatRate.Location = New-Object System.Drawing.Point(115, 128)
$txtRepeatRate.Width = 50
$txtRepeatRate.Text = $Values.AutoRepeatRate
$txtRepeatRate.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtRepeatRate.BackColor = [System.Drawing.Color]::FromArgb(44, 44, 44)
$txtRepeatRate.ForeColor = [System.Drawing.Color]::White
$form.Controls.Add($txtRepeatRate)

# KeyPress event handlers
function OnKeyPress {
    param (
        [System.Object]$sender, 
        [System.Windows.Forms.KeyPressEventArgs]$e
    )
    if ($e.KeyChar -notmatch '[0-9]' -and $e.KeyChar -ne [char][System.Windows.Forms.Keys]::Back) {
        $e.Handled = $true
    }
}


$txtBounceTime.Add_KeyPress({ OnKeyPress -sender $txtBounceTime -e $_ })
$txtDelayTime.Add_KeyPress({ OnKeyPress -sender $txtDelayTime -e $_ })
$txtRepeatDelay.Add_KeyPress({ OnKeyPress -sender $txtRepeatDelay -e $_ })
$txtRepeatRate.Add_KeyPress({ OnKeyPress -sender $txtRepeatRate -e $_ })

$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Size = New-Object System.Drawing.Size(60, 20)
$btnSave.Location = New-Object System.Drawing.Point(65, 160)
$btnSave.Text = "Save"
$btnSave.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnSave.BackColor = [System.Drawing.Color]::FromArgb(44, 44, 44)
$btnSave.ForeColor = [System.Drawing.Color]::White
$btnSave.FlatAppearance.BorderSize = 0

$form.Controls.Add($btnSave)

# Save
$btnSave.Add_Click({
    $enableFilterKeys = if ($chkEnable.Checked) { $true } else { $false }
    $bounceTime = [int]$txtBounceTime.Text
    $delayTime = [int]$txtDelayTime.Text
    $repeatDelay = [int]$txtRepeatDelay.Text
    $repeatRate = [int]$txtRepeatRate.Text

    Set-Flags -enable $enableFilterKeys
    Set-FilterKeys-Reg -bounceTime $bounceTime -delayTime $delayTime -repeatRate $repeatRate -repeatDelay $repeatDelay
    Set-FilterKeys -enable $enableFilterKeys -bounceTime $bounceTime -delayTime $delayTime -repeatRate $repeatRate -repeatDelay $repeatDelay
})

$btnReset = New-Object System.Windows.Forms.Button
$btnReset.Size = New-Object System.Drawing.Size(20, 17)
$btnReset.Location = New-Object System.Drawing.Point(155, 162)
$btnReset.Text = "↻"
$btnReset.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnReset.BackColor = [System.Drawing.Color]::FromArgb(44, 44, 44)
$btnReset.ForeColor = [System.Drawing.Color]::White
$btnReset.FlatAppearance.BorderSize = 0
$form.Controls.Add($btnReset)

# Reset
$btnReset.Add_Click({
    Set-Flags -enable $false
    Remove-ItemProperty -Path $regPath -Name "*"
    Set-FilterKeys -enable $false -bounceTime 0 -delayTime 0 -repeatRate 0 -repeatDelay 0
})

$form.ShowDialog()
