@echo off
rem Builds dist\Starfield.scr with MSVC. Run from an "x64 Native Tools Command Prompt for VS".
cd /d "%~dp0"
if not exist dist mkdir dist
cl /nologo /O2 /W3 /MT /EHsc /DUNICODE /D_UNICODE starfield.cpp /Fe:dist\Starfield.scr /Fo:dist\ ^
  /link /SUBSYSTEM:WINDOWS user32.lib gdi32.lib advapi32.lib comctl32.lib d2d1.lib d3d11.lib dxgi.lib dxguid.lib
if errorlevel 1 exit /b 1
echo Built dist\Starfield.scr
