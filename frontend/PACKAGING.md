# Packaging

## Windows `.exe`

Pré-requis :

- Flutter pour Windows
- Inno Setup 6

Commande :

```powershell
pwsh -File .\scripts\build_windows_installer.ps1
```

Sortie :

```text
build\windows\installer\up2school-setup-<version>.exe
```

L'icône de l'application et de l'installateur provient de :

- `windows/runner/resources/app_icon.ico`

Le script Inno Setup utilisé est :

- `packaging/windows/up2school.iss`

## Linux `.deb`

Pré-requis :

- Flutter pour Linux
- `dpkg-deb`

Commande :

```bash
./scripts/build_linux_deb.sh
```

Sortie :

```text
build/linux/deb/UY1-Lib_<version>_<arch>.deb
```

Le paquet installe :

- l'application dans `/opt/up2school`
- le lanceur desktop dans `/usr/share/applications/up2school.desktop`
- l'icône dans `/usr/share/icons/hicolor/256x256/apps/up2school.png`
