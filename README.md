# Microsoft-Store-Game

    Publishing Multiplayer Online Shooter Game for Windows.

## Build a Store-ready MSIX

The checked-in `play/client.exe` is an x64 console-subsystem executable. Run the packaging script below from PowerShell to create a GUI-subsystem copy and package it as an MSIX. The `Publisher` value must be the exact publisher identity from Partner Center, including the `CN=` prefix.

```powershell
.\scripts\package-msix.ps1 `
    -Publisher 'CN=YOUR_PARTNER_CENTER_PUBLISHER_ID' `
    -PublisherDisplayName 'Warzone3D' `
    -PackageName 'Warzone3D.DeathMatch3D' `
    -Version '1.0.0.0'
```

The script requires the Windows SDK (`makeappx.exe`). It leaves the original executable untouched, verifies the staged executable uses the Windows GUI subsystem, and writes `dist\Warzone3D.DeathMatch3D-1.0.0.0.msix`. For local installation, sign the package with a certificate whose subject matches the package publisher:

```powershell
.\scripts\package-msix.ps1 `
    -Publisher 'CN=YOUR_PARTNER_CENTER_PUBLISHER_ID' `
    -CertificatePath '.\publisher.pfx' `
    -CertificatePassword 'YOUR_CERTIFICATE_PASSWORD'
```

Submit the signed MSIX from a Windows app submission configured for a packaged desktop application. The package identity and publisher must match the Partner Center app registration; the placeholder values used for local validation are not submittable.

<img width="1536" height="1024" alt="GamePlay" src="https://github.com/user-attachments/assets/aaa017b2-608e-427a-a724-d60c729c9767" />
