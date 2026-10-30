@echo off
rem Builds dist\Starfield.scr with MSVC. Run from an "x64 Native Tools Command Prompt for VS".
cd /d "%~dp0"
if not exist dist mkdir dist
cl /nologo /O2 /W3 /MT /DUNICODE /D_UNICODE starfield.c /Fe:dist\Starfield.scr /Fo:dist\ ^
  /link /SUBSYSTEM:WINDOWS user32.lib gdi32.lib advapi32.lib dwmapi.lib comctl32.lib shell32.lib
if errorlevel 1 exit /b 1
echo Built dist\Starfield.scr
