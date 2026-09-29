; The Windows installer, built with makensis on the same Linux runner that exports the game.
;
; **Why an installer at all.** The Windows download is a folder and cannot stop being one: the
; GDExtension is a .dll the operating system loads from disk, and `mods/` is loose on purpose because
; players install mods into it. Embedding the .pck removed one loose file; the other two are structural.
; So the choice was "unzip a folder and find the exe" or "run a setup". (2026-09-29)
;
; **Per-user, not Program Files.** RequestExecutionLevel user installs into %LOCALAPPDATA% and never
; shows an administrator prompt. An unsigned installer already has one warning to get past; asking for
; admin on top of that is asking a friend to do two frightening things in a row. It also means `mods/`
; is writable by the person playing, which a Program Files install would not be without more work.
;
; **This does not remove the SmartScreen warning.** Nothing does, short of signing and accumulated
; reputation - and an unsigned *installer* is, if anything, looked at harder than an unsigned game.
; What it removes is the unzipping.
;
;   makensis -DVERSION=0.42.1 -DSOURCE=build/windows -DOUTFILE=build/Quarrowen-Setup.exe \
;            tools/windows_installer.nsi

!ifndef VERSION
  !error "VERSION is required: makensis -DVERSION=x.y.z ..."
!endif
!ifndef SOURCE
  !define SOURCE "build/windows"
!endif
!ifndef OUTFILE
  !define OUTFILE "build/windows/Quarrowen-Setup.exe"
!endif

!define NAME "Quarrowen"
!define PUBLISHER "Quarrowen"
!define REGKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${NAME}"

Name "${NAME} ${VERSION}"
OutFile "${OUTFILE}"
Unicode true
RequestExecutionLevel user
InstallDir "$LOCALAPPDATA\${NAME}"
; Reinstalling over an existing copy keeps whatever folder it went into last time.
InstallDirRegKey HKCU "Software\${NAME}" "InstallDir"
ShowInstDetails show
ShowUninstDetails show
SetCompressor /SOLID lzma
BrandingText "${NAME} ${VERSION}"

!include "MUI2.nsh"
!define MUI_ABORTWARNING
!define MUI_ICON "..\assets\icon.ico"
!define MUI_UNICON "..\assets\icon.ico"
!define MUI_FINISHPAGE_RUN "$INSTDIR\Quarrowen.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Play Quarrowen"

!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Section "Install"
  SetOutPath "$INSTDIR"
  ; **Worlds live in the user's profile, not here**, so replacing these files never touches a save.
  File "${SOURCE}\Quarrowen.exe"
  File "${SOURCE}\quarrowen_native.dll"
  SetOutPath "$INSTDIR\mods"
  File /r "${SOURCE}\mods\*.*"
  SetOutPath "$INSTDIR"

  CreateDirectory "$SMPROGRAMS\${NAME}"
  CreateShortcut "$SMPROGRAMS\${NAME}\${NAME}.lnk" "$INSTDIR\Quarrowen.exe" "" "$INSTDIR\Quarrowen.exe" 0
  CreateShortcut "$SMPROGRAMS\${NAME}\Uninstall ${NAME}.lnk" "$INSTDIR\uninstall.exe"

  WriteUninstaller "$INSTDIR\uninstall.exe"
  WriteRegStr HKCU "Software\${NAME}" "InstallDir" "$INSTDIR"
  ; So it appears in Settings > Apps like anything else, and can be removed the ordinary way.
  WriteRegStr HKCU "${REGKEY}" "DisplayName" "${NAME}"
  WriteRegStr HKCU "${REGKEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${REGKEY}" "Publisher" "${PUBLISHER}"
  WriteRegStr HKCU "${REGKEY}" "DisplayIcon" "$INSTDIR\Quarrowen.exe"
  WriteRegStr HKCU "${REGKEY}" "UninstallString" "$\"$INSTDIR\uninstall.exe$\""
  WriteRegDWORD HKCU "${REGKEY}" "NoModify" 1
  WriteRegDWORD HKCU "${REGKEY}" "NoRepair" 1
SectionEnd

Section "Uninstall"
  ; **Named removals, not `RMDir /r $INSTDIR`.** If InstallDir were ever wrong or empty, a recursive
  ; delete would take the wrong folder with it. Everything this installer writes is removed by name,
  ; and the directory itself only goes if it ends up empty.
  Delete "$INSTDIR\Quarrowen.exe"
  Delete "$INSTDIR\quarrowen_native.dll"
  Delete "$INSTDIR\uninstall.exe"
  RMDir /r "$INSTDIR\mods"
  RMDir "$INSTDIR"

  Delete "$SMPROGRAMS\${NAME}\${NAME}.lnk"
  Delete "$SMPROGRAMS\${NAME}\Uninstall ${NAME}.lnk"
  RMDir "$SMPROGRAMS\${NAME}"

  DeleteRegKey HKCU "${REGKEY}"
  DeleteRegKey HKCU "Software\${NAME}"
SectionEnd
